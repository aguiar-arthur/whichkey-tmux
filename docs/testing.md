# Testing

```sh
make lint   # shellcheck + shfmt -d (config: .shellcheckrc, .editorconfig)
make unit   # tests/unit.sh: lib/ functions, no tmux server, < 1 s
make e2e    # tests/e2e.sh: a private tmux server with real clients, ~20 s
make test   # unit + e2e
```

Requirements: tmux 3.4+, bash, Python 3 (e2e only), shellcheck and shfmt
(lint only). Both test scripts print `ok`/`FAIL` lines and exit with the
number of failures.

## Unit tests (tests/unit.sh)

Source the libraries and call functions directly; `check <name> <expected>
<actual>`. Anything that would call tmux gets a stand-in: define a `tmux()`
shell function after sourcing, and it shadows the real binary.

```bash
tmux() { printf 'a%s%sc d\n' "$WK_SEP" "$WK_SEP"; }
read_formats client x '#{x}' y '#{y}' z '#{z}'
check "read_formats keeps empty fields" "a||c d" "$x|$y|$z"
```

Set `WK_TMUX_VERSION` before calling `bindings.sh` functions; it selects the
way bindings are read. Fixtures of `list-keys` output must look like real
tmux output, including its order (see `parse_list_keys`).

Run them under bash 3.2 too: `/bin/bash tests/unit.sh` on macOS. CI does.

Add a unit test for any pure logic: quoting, key decoding, layout, styles,
parsing.

## End-to-end tests (tests/e2e.sh)

### Setup

- A private server: `tmux -L whichkey-test-<pid>`, removed on exit along
  with its socket. `XDG_CACHE_HOME` points into the work directory, so the
  defaults cache and debug log never touch `~/.cache`.
- Two configs, written by the test: `tmux.conf` (catalog) and `auto.conf`
  (adds `prefix2 C-a`, `@whichkey-auto on`, `@whichkey-delay 100`).
- Each test binding records that it ran: `bind q set -g @wk-test q`. A check
  then waits for `@wk-test` to hold the expected value.
- Panes run `stty raw -echo; exec cat >/dev/null` with `remain-on-exit`, so a
  stray key never reaches a shell (a stray `C-d` once ended the session).
- Clients are real: `tests/pty_run.py <rows> <cols> <log> tmux attach`
  gives each its own pseudo-terminal of a fixed size, copies what the test
  types into it and everything tmux draws into a log file.

### Helpers

| Helper | Does |
|---|---|
| `start <rows> [config]` | new server, attach the main client (`$main`, typed into through fd 3) |
| `attach <fd> <rows> <name>` | attach another client; sets `$client` |
| `key <key>...` | `send-keys -c $client -K` (single characters as `-H` hex) |
| `typed <bytes>` | write raw bytes (`printf %b`) to the main client's terminal |
| `mark` / `drawn <text>` | has `<text>` been drawn since the mark? (greps the client log) |
| `open <text> <key>...` | mark, press keys, wait until `<text>` is drawn |
| `wait_for <cmd...>` | poll a command for up to 3 s |
| `expect_fired <name> <value>` | wait for `@wk-test` = value, check, reset it |
| `expect_drawn <name> <text>` | wait for text, pass or fail |
| `binding <table> <key>` | the command bound to a key, from plain `list-keys` (works on every version) |

### Rules

- **Poll, don't sleep.** Wait for something observable (`wait_for`,
  `expect_*`). The only fixed sleeps check that something does *not* happen.
- **Menus and popups are driven with `typed`.** Before tmux 3.8, a menu does
  not match `send-keys -K` keys to its items, and on tmux 3.4 a popup does
  not get `Escape` from it. Typed bytes go through tmux's input parsing
  exactly like a user's. `key` is fine for keys that go to a key table
  (`C-b`, `C-b Space`).
- **`mark` before acting**, or `drawn` may match output from an earlier
  test.
- **`drawn` checks bytes, not the screen.** Text that was drawn and then
  scrolled away still matches. To see what the user sees, look at a picture
  (the demo screenshots).
- **Close what you open**: a popup left open swallows every following key.
- A second client gets its own fd: `printf '\033' >&4`.

### Switches

- `WHICHKEY_TMUX_LIST=all` / `plain`: read bindings the tmux 3.7 / 3.4–3.6
  way on a current tmux. Run `WHICHKEY_TMUX_LIST=plain make e2e` after
  touching `bindings.sh`.
- `E2E_WORK=<dir>`: work in `<dir>` and keep it. Also turns on
  `@whichkey-debug` from the start and runs the server with `-vv`. The
  directory then holds:
  - `main.log`, `second.log`: what each client drew (last server only);
  - `debug-<n>.log`: the plugin's `set -x` trace for server `n`;
  - `tmux-server-<pid>.log`: tmux's own log (commands, key handling).

## CI (.github/workflows/ci.yml)

| Job | Runs |
|---|---|
| lint | `make lint` on Ubuntu |
| unit | Ubuntu (bash 5), macOS (`/bin/bash` 3.2) |
| e2e (tmux X, Linux) | tmux 3.4, 3.5a, 3.6b, 3.7c, 3.8 built from release tarballs (cached); a probe step prints how that tmux answers the commands the plugin uses; `E2E_WORK` set; on failure the work directory is uploaded as artifact `e2e-tmux-X` |
| e2e (macOS) | Homebrew tmux, with `/bin` first in `PATH` so the scripts run on bash 3.2 |

When a new tmux is released, add it to the matrix.

### Reading a CI failure

```sh
gh run list --limit 3
gh run view <id> --log-failed | grep -E 'FAIL|failed'
gh run download <id> -n e2e-tmux-3.4 -D /tmp/e2e-3.4
```

Then, in the artifact:

1. `debug-<n>.log`: find the run (`grep '^== '`), read the trace up to the
   tmux error (errors appear as plain lines between `+` trace lines).
2. `tmux-server-*.log` (largest = the auto-mode server): find the test's
   input (`grep -n 'command: send-keys'`), then read what tmux did next:
   `key table root`, `found in key table`, `cmdq_fire_command ...`. A
   `cmdq_next <client-N>: waiting` that never ends is a `display-popup`
   still open.
3. The probe step's output in the job log shows the raw behaviour of that
   tmux version.

Confirm a suspected tmux behaviour in tmux's source for that version before
working around it (`gh api repos/tmux/tmux/contents/<file>.c?ref=<tag>`),
and record it in [tmux-compatibility.md](tmux-compatibility.md).

## Demo (.github/workflows/demo.yml)

`docs/demo.tape` (vhs) records `docs/demo.gif` with `docs/demo.conf`. Run
the "Demo" workflow by hand after a visible change, download the `demo`
artifact, look at `shots/*.png` (popup, group, catalog), and commit the GIF
if they are right. The screenshots are how the missing first popup row was
found: the e2e tests passed.
