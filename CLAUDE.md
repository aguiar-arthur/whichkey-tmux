# CLAUDE.md

Guide for Claude Code (and humans) working on whichkey-tmux: a
which-key plugin for tmux, in bash. It shows a catalog menu of key bindings
on `prefix Space` and, in auto mode, a popup of the user's bindings after a
pause on the prefix. It reads the live bindings from tmux every time; it has
no config of its own and no build step.

## Read first

| Doc | When |
|---|---|
| [docs/architecture.md](docs/architecture.md) | Before any change: files, flows, state the plugin owns |
| [docs/decisions.md](docs/decisions.md) | Before changing how something works: why it is the way it is, what was rejected |
| [docs/tmux-compatibility.md](docs/tmux-compatibility.md) | Before calling a tmux command in a new way, or when something fails on one tmux version |
| [docs/testing.md](docs/testing.md) | Before writing tests, and to debug a CI failure |
| [README.md](README.md) | What users see: install, options, troubleshooting |

## Commands

```sh
make lint                         # shellcheck + shfmt -d; must be clean
make fmt                          # shfmt -w
make unit                         # tests/unit.sh, < 1 s
/bin/bash tests/unit.sh           # same under bash 3.2 (macOS)
make e2e                          # tests/e2e.sh, ~20 s, needs tmux 3.4+ and python3
WHICHKEY_TMUX_LIST=plain make e2e # e2e with the tmux 3.4-3.6 way of reading bindings
WHICHKEY_TMUX_LIST=all make e2e   # ... and the tmux 3.7 way
E2E_WORK=/tmp/e2e make e2e        # keep logs, plugin trace and tmux -vv logs in /tmp/e2e
```

The tests use a private server (`tmux -L whichkey-test-<pid>`) and a private
cache directory. They never touch the user's tmux server or `~/.cache`.

## Map

```
whichkey.tmux          entry point; run on every config load; must be idempotent
scripts/menu.sh        catalog menu (display-menu) for one table and page
scripts/auto.sh        after the prefix delay: decide, lay out the grid, open the popup
scripts/popup.sh       inside the popup: draw, read one key, forward it to tmux
scripts/lib/*.sh       sourced libraries (see docs/architecture.md for each)
tests/unit.sh          lib/ functions with a fake tmux()
tests/e2e.sh           real server + clients on pseudo-terminals (tests/pty_run.py)
docs/                  internals docs; demo.tape/demo.conf record demo.gif
.github/workflows/     ci.yml (lint, unit, e2e matrix tmux 3.4-3.8 + macOS), demo.yml
```

## Rules you must follow

### Shell

1. **bash 3.2.** No associative arrays, `mapfile`/`readarray`, `${var,,}`,
   `${var^^}`, `declare -n`, `{fd}>` redirections, `printf '%(...)T'`. macOS
   runs the scripts with `/bin/bash` 3.2.
2. **Helpers return through `printf -v`.** A function that produces a string
   takes the target variable's name as `$1` and assigns with
   `printf -v "$1" ...`. Do not add `$(helper ...)` calls inside loops: each
   is a fork, and menus have ~100 bindings.
3. **Helper locals start with `_`.** `printf -v name` assigns to the
   innermost variable called `name`; a helper with `local table` cannot set
   its caller's `table`. This bug has happened twice here.
4. **Never `printf -v var ''`.** An empty format does not assign; use
   `printf -v var '%s' ''`.
5. **Arrays between steps are UPPERCASE globals** (`WK_KEYS`, `ITEM_LABELS`,
   `CELL_KEYS`), documented on the function that fills them.
6. **No new runtime dependencies.** POSIX tools only (`dd`, `od`, `stty`,
   `mktemp`, `wc`). Python is for tests.
7. Every function gets a comment: `# name <args>: what it does`, in the
   style of the existing code. Comments say why, not what.

### tmux

8. **Never call `list-keys` or parse key tables directly.** Use
   `load_bindings`, `list_bindings` or `lookup_command` (bindings.sh). They
   handle the three ways tmux 3.4-3.8 can list keys, and they produce
   identical output. `list-keys -F` does not exist before 3.7, and 3.7
   prints a one-binding result to the status line instead of stdout.
9. **Read many values in one call:** `read_formats <client> var fmt ...`.
   It also undoes the `\037` escaping of tmux < 3.7.
10. **Quote for the right layer**, with the helper for it:

    | Into | Helper |
    |---|---|
    | a `/bin/sh` command line (run-shell, popup command) | `sh_quote` |
    | a tmux command string (bind-key with one string, menu item command) | `tmux_quote` |
    | anything tmux expands as a format: menu names and commands, `display-message` text, menu and popup titles, run-shell | `format_escape` (`#` → `##`) |
    | a tmux CLI argument that may end in `;` | `argv_escape` |
    | a key to `send-keys` | `key_hex` → `-H <hex>` for single ASCII characters |

    Strings often pass through several layers; apply them innermost first
    (see `menu_command`, `auto_command`).
11. **Every key must reach tmux.** Anything that reads keys (the popup)
    forwards what it does not understand. Unknown input closes the popup and
    returns the client to the root table.
12. **whichkey.tmux talks to tmux through `queue`/`run_queue`**, reading
    settings with one `read_settings` call: it runs on every tmux start and
    reload. A failing command in a tmux sequence stops the rest, so queue
    commands that commit a change (`prefix None`) after those that prepare
    it, and restore the prefix first when undoing.
13. **Plugin state must be undoable.** Anything `setup_auto` changes in the
    server (options, bindings, hooks) needs its reversal in `teardown_auto`
    and an entry in the state table of docs/architecture.md. Running
    `whichkey.tmux` twice must give the same result as once.
14. **Supported tmux: 3.4+.** If you use a tmux feature, check
    docs/tmux-compatibility.md and let CI prove it on every version. Record
    any new version difference there, with its evidence.

### Tests

15. **Pure logic gets a unit test; anything that talks to tmux gets an e2e
    check.** A bug fix gets the test that would have caught it.
16. **In e2e, drive menus and popups with `typed` (raw bytes), not `key`.**
    Before tmux 3.8 menus ignore `send-keys -K` keys, and tmux 3.4 popups do
    not get Escape from it.
17. **Poll, don't sleep** (`wait_for`, `expect_fired`, `expect_drawn`), and
    `mark` before acting.
18. **e2e passing is not "it looks right".** `drawn` matches bytes even if
    they scrolled away. For anything visual, run the Demo workflow and look
    at the screenshots.

## Definition of done

- [ ] `make lint` clean.
- [ ] `make unit` and `/bin/bash tests/unit.sh` pass.
- [ ] `make e2e` passes; also `WHICHKEY_TMUX_LIST=plain make e2e` and
      `WHICHKEY_TMUX_LIST=all make e2e` if you touched how bindings are read.
- [ ] After pushing, every CI job is green (tmux 3.4, 3.5a, 3.6b, 3.7c, 3.8,
      macOS). If one fails, read its artifact (docs/testing.md, "Reading a CI
      failure"); do not guess.
- [ ] Visible change: Demo workflow run, screenshots checked, GIF updated.
- [ ] Docs updated (below).

## Keep the docs true

| You changed | Update |
|---|---|
| an option (new, default, meaning) | `scripts/lib/options.sh`, README options table |
| user-visible behaviour | README |
| files, flows or state the plugin owns | docs/architecture.md |
| a design choice, or rejected an alternative worth remembering | docs/decisions.md |
| a workaround for a tmux or bash version | docs/tmux-compatibility.md |
| test helpers, switches, CI | docs/testing.md |
| commands, rules or layout in this file | CLAUDE.md |

## Project conventions

- **No releases**: no tags, GitHub releases or changelog. Users install
  `main`; commit messages are the history.
- **Commits**: imperative subject (≤ 72 characters), body explaining the
  problem, the evidence and the fix. One concern per commit. Do not commit
  until the checks above pass.
- **Language**: code, comments, docs and commit messages in English.
- **Formatting**: tabs in shell (`.editorconfig`, applied by `shfmt`).

## Pitfalls that already bit this project

- The popup grid ended with a newline: at the bottom of the popup it
  scrolled the first row away. e2e passed; screenshots showed it.
- Home/End reach a popup as `ESC [1~` / `ESC [4~`, not `ESC [H` / `ESC [F`.
  Decode what tmux actually sends; measure it by typing into a real client.
- The plain `list-keys` parser took the key `-` for a flag; an empty label
  made `display-menu` read the item as a separator and shift every argument.
- `printf -v var ''` silently left stale values in place.
- A note starting with `+` on a group rendered as `++name`.
- A popup left open in one e2e test swallowed the keys of the next ones,
  twice: once because tmux 3.4 popups ignore Escape from `send-keys -K`,
  once because the test did not wait for a typed Escape (held for
  `escape-time`) to close it. Use `close_popup`.
- Messages and popup titles were sent without `format_escape`: tmux read
  the user's regex or table name as a format.
- `setup_auto` set `prefix None` before binding the key: a failed binding
  would have left tmux without a prefix.
- Guessing at a CI failure cost several runs; the per-server debug trace and
  `tmux -vv` log in the artifact found each cause in one read.
