# Design decisions

Why whichkey-tmux is built the way it is. Each entry: the problem, what we
chose, and what we rejected. Read this before changing one of these areas;
most of the "obvious" alternatives were tried or considered and fail in a
specific way.

## 1. Read the live bindings; no menu definition

**Problem.** A which-key menu needs a list of keys and labels.
**Decision.** Read `tmux list-keys` every time a menu or popup opens. Labels
are binding notes (`bind -N`), falling back to the command.
**Rejected.** A separate YAML/config of menus: it drifts from `tmux.conf`
and doubles the work. Caching the user's bindings:
they change on every reload; reading them is fast enough.

## 2. Replay the key instead of running the command

**Problem.** Choosing a menu item should do exactly what the key does.
**Decision.** The item runs `switch-client -T <table> ; send-keys -K <key>`:
tmux handles the key as if typed.
**Rejected.** Copying `#{key_command}` into the menu item: the printed
command must be re-parsed (quoting, `{ }` blocks, `\;`), formats would be
expanded twice, and `-r` repeat would be lost.

## 3. Auto mode takes over the prefix key

**Problem.** tmux handles the prefix inside the server, before bindings and
hooks, so there is nothing to attach a "wait, then show" timer to.
**Decision.** Set `prefix` (and `prefix2`) to `None` and bind the key itself
in `root`, `copy-mode` and `copy-mode-vi` to a trigger that switches to the
prefix table and schedules `auto.sh` with `run-shell -b -d`. Save the real
key in `@whichkey-prefix` so reloads and teardown work, and replace
`send-prefix` with `send-keys <key>`.
**Consequences.** `#{client_prefix}` still works. The prefix stays rewired
until auto mode is turned off and the config reloaded, or the server
restarts; removing the plugin line alone is not enough (README: Uninstall).
**Rejected.** `client-*` hooks or `status-interval` polling: no hook fires on
the prefix, and polling is either slow or expensive.

## 4. Detect "a key was pressed" from side effects

**Problem.** tmux cannot cancel a pending `run-shell -d`, and has no
key-pressed event.
**Decision.** After the delay, `auto.sh` shows the popup only if the client
is still outside the root table, no newer prefix press happened on that
client (sequence number), and session/window/pane/layout are unchanged
(state snapshot taken when the trigger ran). It checks again right before
drawing.
**Consequences.** A repeat (`-r`) binding that changes none of session,
window, pane or layout can still let the popup appear (documented).
**Rejected.** `#{client_activity}`: one-second resolution. `#{client_flags}`:
no flag for "a key was pressed".

## 5. Sequence number per client, through option names

**Problem.** A single global counter meant a prefix press on one attached
client cancelled a popup pending on another.
**Decision.** The trigger bumps `@whichkey-seq` and copies it to
`@whichkey-seq-#{client_name}` (`set-option` expands formats in the option
name). A `client-detached` hook removes the per-client option.
**Rejected.** Incrementing the per-client option directly:
`#{@whichkey-seq-#{client_name}}` does not work, tmux formats do not nest.
Keying by `#{client_pid}`: empty inside the `client-detached` hook
(`#{hook_client}` is the name).

## 6. Popup reads raw bytes and forwards one key

**Problem.** The popup must not swallow keys: any key, listed or not, must
reach tmux.
**Decision.** `popup.sh` puts its terminal in raw mode before drawing, reads
one key's bytes, decodes them to a tmux key name the way tmux encodes keys
for a popup, closes the popup and sends the key to the client's table with
`send-keys -K`. Unknown input closes the popup and leaves the prefix table.
**Rejected.** Making the popup a `display-menu`: menus capture navigation
keys (`j`, `k`, `q`, arrows) and only offer listed items.

## 7. Bash 3.2, no dependencies

**Problem.** macOS ships bash 3.2 as `/bin/bash`, and TPM plugins run under
whatever bash is on `PATH`.
**Decision.** Every script runs on bash 3.2: no associative arrays,
`mapfile`, `${var,,}`, `{fd}>` or `declare -n`. Only POSIX tools (`dd`, `od`,
`stty`, `mktemp`). Python is used only by the tests.

## 8. Return values through `printf -v`

**Problem.** `$(func)` forks a subshell; in per-binding loops that cost
~500 ms per menu.
**Decision.** Helpers take the name of the variable to set as their first
argument and assign with `printf -v`. Their locals start with `_`, because
`printf -v name` assigns to the innermost variable called `name`: a helper
with `local table` cannot set its caller's `table`. Script steps pass arrays
on in UPPERCASE globals.
**Watch out.** `printf -v var ''` (empty format) does not assign; write
`printf -v var '%s' ''`.

## 9. Field separator `\x1f`

**Problem.** `list-keys -F` and `display-message -p` return several fields
per line; notes can be empty.
**Decision.** Separate fields with `\x1f` (ASCII unit separator): not
whitespace, so `IFS=$'\x1f' read` keeps empty fields, and in practice it
does not appear in notes or commands. tmux before 3.7 prints it as the text `\037`;
`read_formats` turns that back.
**Rejected.** Tab: whitespace, so `read` merges empty fields.

## 10. "Your bindings" = differs from a config-less tmux

**Problem.** tmux has ~90 default prefix bindings; the popup should show
what the user configured.
**Decision.** Compare each `key SEP note SEP command` line with the same
table on a throwaway server started with `-f /dev/null`, cached per tmux
version.
**Rejected.** A hard-coded default list: wrong on every tmux release.
Comparing keys only: a default key rebound to a new command must count as
the user's.

## 11. Three ways to read a table, chosen by version

**Problem.** `list-keys -F` does not exist before 3.7, and in 3.7 prints a
table with one binding to the status line.
**Decision.** `-F -T <table>` on 3.8+, `-F` for all tables filtered by
`#{key_table}` on 3.7, and the plain `list-keys` output parsed (plus
`list-keys -N` for notes) before that. All three produce the same lines;
`WHICHKEY_TMUX_LIST` forces one for tests.
**Rejected.** Always parsing plain output: `-F` is exact and needs no
unescaping. Feature-detecting with a probe call: costs a tmux call per run;
the version is already read with the other formats.

## 12. Single ASCII keys are sent as hex

**Problem.** `;`, `{`, `"`, `#`, `'` and `\` are special to the tmux
command parser or CLI, in different ways.
**Decision.** Send any single ASCII character with `send-keys -K -H <hex>`.
Named keys are passed as is, with a trailing `;` escaped (`M-;`).
**Rejected.** Quoting each special character: several are special in more
than one layer (shell, CLI argv, command parser, formats).

## 13. Paginate the catalog

**Problem.** A `display-menu` taller than the client is silently not drawn.
**Decision.** Fit pages to `client_height - 4` rows, with "Next page" /
"Previous page" items. The user's bindings fill page 1 first.

## 14. Debug through a flag file

**Problem.** Bug reports need traces, but scripts run inside tmux with no
terminal.
**Decision.** `@whichkey-debug on` makes `whichkey.tmux` create
`~/.cache/whichkey-tmux/debug.on`; every script checks for that file first
thing (no tmux call) and, if present, sends `set -x` output to `debug.log`.
The log is created with mode 600: it shows the commands of the user's
bindings, which can hold tokens or paths.
**Rejected.** An environment variable set with `set-environment -g`: it
works too, but adds server state that must be cleaned up, while the file is
checked with a single `stat`.

## 15. Tests drive real clients; menus and popups by typing

**Problem.** Most bugs were in the interaction between tmux, terminals and
the scripts, and only showed on some tmux versions.
**Decision.** e2e runs a private server with real clients on
pseudo-terminals (`pty_run.py`), checks that bindings actually fire, and
runs in CI against every tmux release from 3.4. Menus and popups are driven
by typing raw bytes, because before 3.8 menus ignore `send-keys -K` keys and
3.4 popups do not get Escape from it.

## 16. Load in few tmux calls, ordered for safety

**Problem.** `whichkey.tmux` runs on every tmux start and config reload, and
each tmux call costs milliseconds (~200 ms with 17 calls). It also changes
the prefix: a half-applied change could leave tmux without one.
**Decision.** Read every setting with one `display-message`, list each key
table at most once, and send the changes as one command sequence per
concern (menu keys, auto mode). tmux stops a sequence at the first failing
command, so `setup_auto` queues `prefix None` after every binding it needs,
and `teardown_auto` restores the prefix first.

## 17. No releases

The project ships from `main`; there are no tags, GitHub releases or
changelog. TPM installs `main`. CI on every push keeps it usable, and bug
reports give the installed commit.

## 18. Search in our own popup, not fzf

**Problem.** With dozens of bindings across tables and groups, scanning a
menu is slow; users want to type a word.
**Decision.** `search.sh` collects the prefix table, every reachable group
and the user's root bindings into a file, and `search-popup.sh` filters it
in bash as the user types: substring matches first, then characters in
order (`match_rank`). Each result shows the whole key sequence (`C-b w n`),
and Enter replays the key in its table like a menu item (decision 2).
**Rejected.** fzf or any other program: a runtime dependency (decision 7).
A `display-menu` with a filter: menus cannot take free text. Hiding the
search behind a default key: `prefix /` is tmux's "describe key", so the
key is opt-in (`@whichkey-search-key`) and the catalog always has a
Search… item.

## 19. Backspace goes back, unless the table binds it

**Problem.** In a group popup, Escape closes everything; there was no way
back to the table above.
**Decision.** `auto.sh` gets the path of tables that led to the popup; the
title shows it (`prefix › window`), and Backspace reopens the popup one
level up at once. Only when the table does not bind `BSpace` itself, so
every key still reaches tmux (CLAUDE.md rule 11).
**Rejected.** Escape going back one level: Escape has always closed the
popup, and closing must stay one key away.

## 20. tmux's bindings in the popup when the user has none

**Problem.** The popup shows the user's bindings. On a fresh install there
are none, so auto mode showed nothing and looked broken.
**Decision.** `@whichkey-popup-defaults auto` (default) adds tmux's own
bindings, filtered like the catalog, when none of the user's remain after
setting aside the plugin's own keys. `on` always adds them after the
user's; `off` never.
**Rejected.** Always showing the defaults: ~60 cells drown the handful a
user defined, which are the ones they forget.

## 21. A doctor script instead of more troubleshooting text

**Problem.** The common failures (plugin not loaded, prefix set after the
plugin, a key rebound later) were documented, but each needed the user to
run `tmux show` and `list-keys` and read the output.
**Decision.** `scripts/doctor.sh` checks each of them against the running
server and says what to do. It also lists bindings without notes and the
tmux defaults the user replaced, as advice. Read-only; exit status = number
of problems.

## 22. No Nix package

The project does not ship a Nix flake or package. Install with TPM or a
clone (README). Supporting a package means a CI job and a lock file to
keep current for a channel the maintainer does not use.
