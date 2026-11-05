# Contributing

Bug reports and pull requests are welcome. For a bug, the issue form asks for
your tmux and bash versions; a debug log (`set -g @whichkey-debug on`) helps
most.

## Setup

You need tmux 3.4+, bash, Python 3 (for the e2e test's pseudo-terminals),
[shellcheck](https://www.shellcheck.net) and [shfmt](https://github.com/mvdan/sh).

```sh
make lint   # shellcheck and shfmt -d
make fmt    # shfmt -w
make test   # tests/unit.sh and tests/e2e.sh
```

CI runs the same on Linux with every tmux release from 3.4, and on macOS
with the system bash 3.2.

Two variables help when something only breaks on another tmux:

- `WHICHKEY_TMUX_LIST=all` or `=plain` makes a current tmux read bindings
  the way tmux 3.7 or 3.4 to 3.6 have to (see `list_bindings`), so
  `WHICHKEY_TMUX_LIST=plain make e2e` covers the old code path locally.
- `E2E_WORK=<dir> make e2e` keeps the test's files in `<dir>`: client
  output, the plugin's debug trace per server, and tmux's own server log.
  CI uploads them as an artifact when e2e fails.

## Code layout

```
whichkey.tmux        entry point: binds the catalog key, turns auto mode on/off
scripts/menu.sh      the catalog menu (prefix Space)
scripts/auto.sh      auto mode: decides whether to show the popup, lays out the grid
scripts/popup.sh     runs inside the popup: reads one key and forwards it
scripts/lib/
  quote.sh           quoting for tmux, formats and sh (pure)
  options.sh         defaults for every @whichkey-* option
  tmux.sh            queries to the tmux server
  bindings.sh        parses a key table; tells your bindings from tmux's defaults
  keys.sh            terminal bytes -> key names, and how to send a key (pure)
  layout.sh          pagination and grid arithmetic (pure)
  style.sh           tmux styles -> terminal escape sequences (pure)
  automode.sh        shared by the prefix trigger, auto.sh and popup.sh
  debug.sh           the @whichkey-debug trace
tests/unit.sh        the lib/ functions, with a fake tmux where needed
tests/e2e.sh         a real tmux server and clients
tests/pty_run.py     runs a client on a pseudo-terminal
docs/demo.tape       records docs/demo.gif (the "Demo" workflow runs it)
```

## Conventions

- **bash 3.2**: no associative arrays, no `mapfile`, no `${var,,}`, no
  `{fd}>` redirections.
- **No subshells in loops.** Helpers assign to the variable named by their
  first argument with `printf -v`, and their locals start with `_` so they
  never shadow the caller's variable. Script steps pass arrays on in
  UPPERCASE globals, since bash cannot return arrays.
- **Drive menus and popups by typing in tests.** Before tmux 3.8, menus
  ignore keys from `send-keys -K`, and tmux 3.4 popups do not get Escape
  from it; `typed` in `tests/e2e.sh` writes real bytes instead.
- **Every key must reach tmux.** Anything that reads keys (the popup) has to
  forward what it does not understand rather than swallow it.
- New behaviour gets a test: a unit test for pure logic, an e2e check for
  anything that talks to tmux.
