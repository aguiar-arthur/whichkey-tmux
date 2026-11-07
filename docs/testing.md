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
parsing, search matching.

`read_key` reads from standard input, so it is tested on a pipe with `stty`
stubbed out: `printf '\033[B\033[B' | read_keys` must give two keys. Keys
typed quickly reach a popup in one read; that is what this catches.

`whichkey.tmux` runs `main` only when executed, so the tests source it and
call `main` against a fake server: `fake_format` answers `display-message`
from `F_*` variables, `list-keys` answers from `F_LIST_<table>`, and every
call is recorded in `CALLS`. The checks look at the order of commands inside
a call (`before`, `call_with`) and at the number of calls.

## End-to-end tests (tests/e2e.sh)

### Setup

- A private server: `tmux -L whichkey-test-<pid>`, removed on exit along
  with its socket. `XDG_CACHE_HOME` points into the work directory, so the
  defaults cache and debug log never touch `~/.cache`.
- Three configs, written by the test: `tmux.conf` (catalog, with
  `@whichkey-search-key /`, a group `g`, a group `O` whose table binds
  `BSpace`, and a root binding `M-z`), `auto.conf` (adds `prefix2 C-a`,
  `@whichkey-auto on`, `@whichkey-delay 100`) and `fresh.conf` (auto mode
  and nothing else: a fresh install).
- Each test binding records that it ran: `bind q set -g @wk-test q`. A check
  then waits for `@wk-test` to hold the expected value.
- Panes run `stty raw -echo; exec cat >/dev/null` with `remain-on-exit`, so a
  stray key never reaches a shell (a stray `C-d` once ended the session).
- Clients are real: `tests/pty_run.py <rows> <cols> <log> tmux -u attach`
  gives each its own pseudo-terminal of a fixed size, copies what the test
  types into it and everything tmux draws into a log file. `-u` makes the
  client draw UTF-8 (`›` in popup titles) whatever the locale.

### Helpers

| Helper | Does |
|---|---|
| `start <rows> [config]` | new server, attach the main client (`$main`, typed into through fd 3) |
| `attach <fd> <rows> <name>` | attach another client; sets `$client` |
| `key <key>...` | `send-keys -c $client -K` (single characters as `-H` hex) |
| `typed <bytes>` | write raw bytes (`printf %b`) to the main client's terminal |
| `close_popup` | type Escape and wait until the main client is back in the root table |
| `mark` / `drawn <text>` | has `<text>` been drawn since the mark? (greps the client log) |
| `open <text> <key>...` | mark, press keys, wait until `<text>` is drawn |
| `wait_for <cmd...>` | poll a command for up to 3 s |
| `expect_fired <name> <value>` | wait for `@wk-test` = value, check, reset it |
| `expect_drawn <name> <text>` | wait for text, pass or fail |
| `binding <table> <key>` | the command bound to a key, from plain `list-keys` (works on every version) |
| `no_search` | no `search-popup.sh` is running (the search has closed) |
| `doctor_says <name> <text>` | the last `doctor.sh` run printed `<text>` |

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
- **Close what you open, and wait for it**: a popup left open swallows the
  next keys. Use `close_popup`: tmux holds a typed Escape for `escape-time`
  (500 ms by default on tmux 3.4; the test config sets 10 ms), so the next
  step must wait until the popup is gone.
- **Type into a popup only once its script has drawn something**: the
  grid of a group popup (`wait_for drawn "group-a"`), the search's hints
  line (`open "esc close" C-b /`). tmux draws the popup's border and title
  before the script sets raw input; in between, a typed `\r` becomes `\n`
  (C-j, "move down" in the search) and `\177` is eaten as "erase".
- `doctor.sh` runs through `run-shell` (so it talks to the test server),
  with its output and exit status written to `$WORK/doctor.txt` and
  `doctor.rc`.
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

The GIF at the top of the README, `docs/demo.gif`, is recorded with
[vhs](https://github.com/charmbracelet/vhs), which plays a script of
keystrokes in a terminal and writes a GIF.

| File | Role |
|---|---|
| `docs/demo.tape` | the script: start tmux, `Ctrl+B` and wait (popup), `\|` (split), `Ctrl+B w` (group popup), Backspace (back up), `Ctrl+B Space` (catalog), arrows, `Ctrl+B /` and `win` (search); `Screenshot` lines at the popup, the group, the catalog and the search |
| `docs/demo.conf` | a tmux config for the demo only: a few noted bindings, a `+window` group, `@whichkey-search-key /`, Dracula colours, a plain `$` prompt |
| `.github/workflows/demo.yml` | runs the tape on Ubuntu (`workflow_dispatch` only) and uploads the GIF and screenshots as the `demo` artifact |

Record it after any visible change:

```sh
gh workflow run demo.yml
gh run watch "$(gh run list --workflow demo.yml --limit 1 --json databaseId -q '.[0].databaseId')"
gh run download "$(gh run list --workflow demo.yml --limit 1 --json databaseId -q '.[0].databaseId')" -n demo -D /tmp/demo
```

Then look at `/tmp/demo/shots/popup.png`, `group.png` (title
`prefix › window`), `catalog.png` and `search.png`. If they are right, copy
`/tmp/demo/demo.gif` to `docs/demo.gif` and commit it.
Locally, with vhs installed (`brew install vhs`), `vhs docs/demo.tape` from
the repository root does the same.

Notes:

- **Look at the screenshots.** They found three bugs the e2e tests passed:
  the popup's first row scrolled out of sight, a group noted `+window` showed
  as `++window`, and the first popup came too late to be recorded.
- CI records with Ubuntu's tmux (3.4 on `ubuntu-latest`), so `demo.conf` must
  not use newer options such as `theme`.
- A vhs screenshot can be taken a step late (one showed the split typed
  after it, with no popup). If a screenshot is wrong but CI is green, look
  at the GIF's frame for that moment before suspecting the plugin.
- `docs/shots/` is ignored by git; only the GIF is committed.
- Changing what the tape shows (keys, the group, timing) means changing
  `demo.conf` and `demo.tape` together.
