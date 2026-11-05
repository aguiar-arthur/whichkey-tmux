# Architecture

whichkey-tmux is a tmux plugin written in bash. It has no build step, no
daemon and no config of its own: every time it shows something, it reads the
live key bindings from tmux. This document describes how it is put together;
[decisions.md](decisions.md) explains why, and
[tmux-compatibility.md](tmux-compatibility.md) lists what differs between
tmux versions.

## Two features

**Catalog** (`prefix Space`): a `display-menu` with every binding of a key
table. The user's own bindings come first, then tmux's defaults after a
separator. Groups (keys that switch to another key table) open a submenu.
Long menus are split into pages.

**Auto popup** (`@whichkey-auto on`): after the prefix key, if no other key
arrives within `@whichkey-delay` ms, a `display-popup` shows a grid of the
bindings the user's config defines in the prefix table. The popup reads one
key and hands it to tmux, so every key works whether listed or not. Group
keys get their own popup the same way.

## Files

```
whichkey.tmux            Entry point. Run once per config (re)load.
scripts/menu.sh          Builds and shows the catalog menu for one table and page.
scripts/auto.sh          Runs after the delay: decides whether to show the popup, lays out the grid.
scripts/popup.sh         Runs inside the popup: draws the grid, reads one key, forwards it.
scripts/lib/             Sourced libraries (no shebang, no side effects but variable definitions).
  quote.sh               Quoting for the tmux parser, formats, argv and sh. Pure.
  options.sh             WK_DEFAULT_* for every @whichkey-* option.
  tmux.sh                read_formats (many formats, one call), version_at_least.
  bindings.sh            Reads a key table (three ways, by tmux version), the defaults cache,
                         user-vs-default classification, labels.
  keys.sh                Terminal bytes -> tmux key names; which keys are sent as hex. Pure.
  layout.sh              Pagination (menu) and grid (popup) arithmetic. Pure.
  style.sh               tmux styles ("fg=magenta,bold") -> SGR escape sequences. Pure.
  automode.sh            Pieces shared by the prefix trigger, auto.sh and popup.sh.
  debug.sh               @whichkey-debug tracing.
tests/unit.sh            Unit tests for lib/, with a fake tmux() where needed.
tests/e2e.sh             End-to-end tests against a private tmux server with real clients.
tests/pty_run.py         Runs a command on a pseudo-terminal (a real tmux client for e2e).
docs/demo.tape, demo.conf  Recording of docs/demo.gif (vhs), run by the Demo workflow.
```

Each script sources the libraries it needs. Most stand alone; the
exceptions are `bindings.sh` (needs `tmux.sh` for `WK_SEP` and
`version_at_least`, and the caller must set `WK_TMUX_VERSION`) and
`automode.sh` (needs `quote.sh`).

## Loading: whichkey.tmux

Run by TPM or by `run-shell` at the end of `tmux.conf`, and again on every
config reload. It must be idempotent, and it delays tmux's start, so it
makes few tmux calls (about four):

1. `read_settings`: the version, every option, `#{prefix}` and `#{prefix2}`
   in one `display-message`.
2. `apply_debug_option`: create (mode 600) or remove the debug files, start
   tracing.
3. Stop with a message below tmux 3.4.
4. `bind_menu_keys`: bind `@whichkey-key` (prefix table) and optionally
   `@whichkey-root-key` (root table) to
   `run-shell -b "menu.sh '#{client_name}' '#{pane_id}' prefix"`. Keys that
   opened the menu before (`@whichkey-bound-key`,
   `@whichkey-bound-root-key`) and no longer should are unbound.
5. `setup_auto` or `teardown_auto`, depending on `@whichkey-auto`.
6. `warm_defaults_cache`: build the defaults cache in the background.

Changes are not sent one by one: `queue` collects tmux commands and
`run_queue` sends them as one `tmux a \; b \; c` call (one for the menu
keys, one for auto mode). Tables are listed at most once per load
(`table_command`). In a tmux command sequence a failing command stops the
rest, and the queue is ordered so that this is safe: `setup_auto` sets
`prefix None` only after every binding it needs, and `teardown_auto`
restores the prefix before anything else.

## Catalog flow

```
prefix Space
  └─ run-shell -b menu.sh <client> <pane> <table> [page]
       read_settings        one display-message for size, options, version
       load_bindings        WK_KEYS/NOTES/COMMANDS/IS_USER/GROUP for <table>
       build_items          filter (is_shown), label, item command
       order_items          user bindings, separator (-1), defaults
       paginate             PER_PAGE/PAGES/START/END from client height
       menu_args            display-menu arguments + page navigation items
       show_menu            tmux display-menu ...
```

A menu item does not re-run the bound command. It presses the key again:

```
switch-client -c <client> -T <table> ; send-keys -c <client> -K <key>
```

(`-H <hex>` for single ASCII characters; no `switch-client` for the root
table.) tmux then runs the binding exactly as if typed, with its own parsing,
`-r` repeat and everything else. A group item instead runs `menu.sh` again
for the group's table. Page items run `menu.sh` for the same table and
another page; their keys are `C-n`/`C-p`, or `NPage`/`PPage` if the table
binds those (`free_key`).

## Auto mode

### Taking over the prefix

tmux switches to the prefix table internally, before any binding runs, so
there is no event to attach a timer to. `setup_auto` therefore:

1. Saves the configured key of `prefix` (and `prefix2`, if set) in
   `@whichkey-prefix` / `@whichkey-prefix2`. On a reload the option is
   already `None`, so the saved key is used. If the config now sets a
   different key, the old one is released first.
2. Binds that key in `root`, `copy-mode` and `copy-mode-vi` (copy modes
   replace the root table) to the **trigger**:

   ```
   switch-client -T prefix ;
   set-option -gF @whichkey-seq '#{e|+:#{@whichkey-seq},1}' ;
   set-option -gF '@whichkey-seq-#{client_name}' '#{@whichkey-seq}' ;
   run-shell -b -d <delay> "auto.sh '#{client_name}' '#{pane_id}' '#{@whichkey-seq}' '<state format>'"
   ```

   `#{client_prefix}` keeps working because the client really is in the
   prefix table.
3. If the prefix table binds the key to `send-prefix` (or `send-prefix -2`),
   replaces it with `send-keys <key>`: `send-prefix` sends the prefix
   option, which is now `None`.
4. Sets the options to `None`: last, so that a failed binding above leaves
   the prefix working.
5. Sets the hook `client-detached[7351]` to remove the client's sequence
   option.

`teardown_auto` (auto off + reload) reverses all of it. Turning the plugin
off by deleting it from `tmux.conf` does **not**: options and bindings live in
the server until it restarts (documented in the README).

### Deciding to show the popup: auto.sh

`run-shell -d` gives the delay, but tmux has no "a key was pressed" event
and no way to cancel a pending `run-shell`. So `auto.sh` checks, after the
delay, that nothing happened:

- the client is not back in the `root` table (a key ran and left the table);
- the client's sequence number (`@whichkey-seq-<client>`) still equals the
  one passed in (no newer prefix press on this client);
- the state `#{session_id}:#{window_id}:#{pane_id}:#{window_layout}`,
  expanded when the trigger ran and passed in, is unchanged (a repeat `-r`
  binding keeps the client in the prefix table, but usually changes this).

It then builds the grid and checks again right before `display-popup`,
because a key may have arrived while it worked.

The popup lists only bindings that differ from tmux's defaults
(`WK_IS_USER`), minus the `send-prefix` stand-ins. Cells are column-major,
`key → label`, padded by character count. If the grid does not fit
(`height - 4` rows), the last cell says `… N more`.

### Inside the popup: popup.sh

`display-popup -E` runs `popup.sh` on its own pseudo-terminal.

1. `stty raw -echo opost min 1 time 0` before drawing, so a key typed the
   instant the popup appears is neither echoed nor line-buffered.
2. Print the grid (no trailing newline: it would scroll the first row away).
3. Read one byte with `dd | od`. For an Escape or a UTF-8 lead byte, read
   the rest with `stty min 0 time 1` (a tenth of a second). A lone Escape
   gets nothing more and closes the popup.
4. `decode_key` turns the bytes into a tmux key name, following what tmux
   sends a popup (see tmux-compatibility.md).
5. `forward_key`:

   ```
   display-popup -C ; switch-client -T <table> ; send-keys -K <key>
   [ ; run-shell -b -d <delay> auto.sh ... ]     # if <key> is a group key
   ```

   The popup is closed first so the key reaches the key table, not the
   popup.

`auto.sh` writes the grid to a `mktemp` file and passes its path;
`popup.sh` deletes it after printing (or `auto.sh` does, if the popup never
opens).

## Reading bindings: bindings.sh

`load_bindings <table>` fills parallel arrays (bash 3.2 cannot return
arrays):

| Array | Content |
|---|---|
| `WK_KEYS` | key name, as tmux prints it (`C-b`, `M-{`, `;`) |
| `WK_NOTES` | `bind -N` note, or empty |
| `WK_COMMANDS` | the bound command, as `list-keys` prints it |
| `WK_IS_USER` | 1 if the line differs from tmux's built-in binding |
| `WK_GROUP` | for `switch-client -T <name>` alone, `<name>`; else empty |

`list_bindings` gets `key SEP note SEP command` lines in one of three ways
(tmux-compatibility.md has the reasons):

| tmux | Way |
|---|---|
| 3.8+ | `list-keys -T <table> -F '#{key_string}SEP#{key_note}SEP#{key_command}'` |
| 3.7 | `list-keys -F '#{key_table}SEP...'` for all tables, filtered |
| 3.4–3.6 | `list-keys -T <table>` parsed (`parse_list_keys`), notes from `list-keys -N -P '' -T <table>` |

`WHICHKEY_TMUX_LIST=all|plain` forces the second or third way for tests. On
tmux 3.8 all three give identical output for every built-in table.

**Defaults.** "Your bindings" are those that differ from a config-less tmux.
`load_defaults` asks a throwaway server (`tmux -L whichkey-defaults-<pid> -f
/dev/null`) for `prefix`, `root`, `copy-mode` and `copy-mode-vi`, caches the
result in `~/.cache/whichkey-tmux/defaults-<version>-<table>`, and removes
the throwaway socket. A binding is the user's if its whole line is not in
that list, so a default rebound to another command counts as the user's.
Tables tmux does not create have no defaults: everything in them is the
user's.

`SEP` is `\x1f`: not whitespace, so `read` keeps empty fields (bindings
without a note).

## State the plugin owns

| Where | What | Written by |
|---|---|---|
| option `prefix`, `prefix2` | `None` while auto mode is on | `setup_auto` |
| option `@whichkey-prefix`, `@whichkey-prefix2` | the user's prefix keys | `setup_auto` |
| option `@whichkey-bound-key`, `@whichkey-bound-root-key` | keys currently bound to the catalog | `bind_menu_keys` |
| option `@whichkey-seq` | global prefix-press counter | trigger |
| option `@whichkey-seq-<client name>` | that client's last counter value | trigger; removed by the detach hook |
| hook `client-detached[7351]` | removes the option above | `setup_auto` |
| bindings | menu key(s); prefix keys in root/copy-mode tables; `send-keys <key>` stand-ins | `whichkey.tmux` |
| `~/.cache/whichkey-tmux/defaults-<version>-<table>` | tmux's built-in bindings | `load_defaults` |
| `~/.cache/whichkey-tmux/debug.on`, `debug.log` | debug flag and trace (mode 600: it shows binding commands) | `apply_debug_option`, `debug_init` |
| `$TMPDIR/whichkey.XXXXXX` | one popup's grid, short-lived | `auto.sh`, removed by `popup.sh` |

`~/.cache` is `$XDG_CACHE_HOME` when set.

## Performance

Everything runs on keypresses, so latency matters: opening the catalog
takes well under 100 ms on tmux 3.8. The rules that keep it there:

- **No subshells in loops.** Helpers return through `printf -v <var>`;
  `$(...)` in a per-binding loop costs a fork each time.
- **One tmux call for many values.** `read_formats` expands all formats in
  a single `display-message`.
- **Defaults are cached** per tmux version and warmed in the background at
  load.
- **Linear parsing.** The pre-3.7 parser walks `list-keys` and
  `list-keys -N` side by side (same order) instead of searching the notes
  for each key, which on bash 3.2 cost ~220 ms per table (now ~45 ms).
