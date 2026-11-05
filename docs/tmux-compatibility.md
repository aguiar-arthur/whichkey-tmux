# tmux and bash compatibility

whichkey-tmux supports tmux 3.4 and newer, and bash 3.2 and newer. CI runs
the e2e test on Linux with tmux 3.4, 3.5a, 3.6b, 3.7c and 3.8, and on macOS
with the latest tmux and the system bash 3.2.

Every quirk below was found the hard way. "Evidence" says how we know:
**CI** (seen in a CI run or its probe step), **source** (read in tmux's
source for that version), **measured** (reproduced locally on tmux 3.8).

## tmux

| Quirk | Versions | Evidence | Handled in |
|---|---|---|---|
| `list-keys -F` does not exist ("unknown flag -F") | 3.4–3.6 | CI | `list_bindings` parses the plain output |
| `list-keys` shows the result in the status line instead of printing it when it has exactly one binding (a one-key table, or `list-keys -T t <key>`) | 3.7 | source (`cmd-list-keys.c`: `n == 1`), CI | `list_bindings` lists all tables with `-F` and filters; `lookup_command` looks the key up in the whole table |
| `display-message -p` prints control characters escaped, so `\x1f` arrives as the text `\037` | 3.4–3.6 | CI | `read_formats` turns `\037` back into `WK_SEP` |
| Menus compare an item's key with the pressed key including flags, so keys injected with `send-keys -K` (flag `KEYC_SENT`) never choose an item; typed keys do | before 3.8 | source (`menu.c`: 3.4 compares `event->key` as is, 3.8 masks flags) | tests type menu keys instead |
| A popup does not receive `Escape` from `send-keys -K` | 3.4 | CI (server log) | tests type Escape |
| `send-keys -K` does not deliver cursor keys (Up, PPage, F-keys) to a popup; real typing does | 3.8 | measured | tests type raw bytes |
| A menu taller than the client is not drawn, silently | all | source (`menu_prepare`), measured | catalog pagination |
| Plain `list-keys` escapes keys: `\;` `\#` `\$` `\"` `\'` `\{` `\}` `\~` `\\`, and quotes some: `"M-{"` | all | measured, CI | `parse_list_keys` |
| `list-keys -N` lists bindings with a note in the same order as `list-keys` | all | measured (3.8), CI (3.4–3.6 pass) | `parse_list_keys` walks both together |
| `list-keys -N` may print a leading space before the key | 3.7 | CI trace | `read` with `IFS=' '` trims it |
| `#{window_layout}` is JSON (classic `b25d,80x24,0,0,0` before) | 3.8 | CI | only compared for equality |
| Formats do not nest: `#{@opt-#{client_name}}` is not expanded | 3.8 | measured | per-client sequence via `set-option -gF '@whichkey-seq-#{client_name}'` (option names are expanded) |
| In a `client-detached` hook, `#{client_pid}` and `#{client_name}` are empty; `#{hook_client}` is the client name | 3.8 | measured | detach hook uses `#{hook_client}` |
| `display-menu` item names and commands are formats: `#` must be `##` | all | measured | `format_escape` |
| A menu item whose name starts with `-` is shown disabled; an empty name is a separator | all | source | labels starting with `-` get a leading space; labels are never empty |
| The tmux CLI treats an argument ending in `;` as a command separator | all | measured | `argv_escape` |
| In a command sequence (`tmux a \; b`), a failing command stops the ones after it | all | measured | `whichkey.tmux` orders its queue |
| `display-message` text and `display-menu`/`display-popup` titles are formats | all | measured | `format_escape` |
| `#{prefix}` and other options can be read as formats during config load | 3.8 | measured, CI | `read_settings` |

### What tmux sends a popup

A popup's program sees keys re-encoded by tmux, which is not always what the
outer terminal sent. Measured on tmux 3.8 by typing into a real client:

| Key | Bytes |
|---|---|
| Up/Down/Right/Left | `ESC [A` … `ESC [D` |
| Home / End | `ESC [1~` / `ESC [4~` (not `ESC [H` / `ESC [F`) |
| F1–F4 | `ESC OP` … `ESC OS` |
| F5–F12 | `ESC [15~` … `ESC [24~` |
| Modifiers | `ESC [1;<m><final>` or `ESC [<n>;<m>~`, with `m` = 1 + shift(1) + meta(2) + ctrl(4) |
| Meta + key | `ESC` then the key (`C-M-a` = `ESC 0x01`) |
| BTab | `ESC [Z` |

`decode_key` in `scripts/lib/keys.sh` accepts these and the common
alternatives (`ESC [H`, `ESC OA`, …).

## bash

| Quirk | Versions | Handled |
|---|---|---|
| No associative arrays, `mapfile`, `${var,,}`, `{fd}>` redirections | 3.2 | not used |
| `printf -v var ''` (empty format) leaves `var` unchanged | all | always `printf -v var '%s' ''` |
| `printf '%-10s'` pads by bytes, so multibyte characters misalign | 3.2 | `render_grid` pads with `${#var}` (characters in a UTF-8 locale) |
| `printf '%d' "'é"` gives the first byte as a negative number | 3.2 | `key_hex` checks `>= 0` |
| `${2//\'/...}` inside double quotes keeps the backslash of `\'` | 3.2 | `sh_quote` keeps pattern and replacement in variables |
| `printf -v name` assigns to the innermost variable called `name`, including the callee's own locals | all | helpers' locals start with `_` |
| `[[ x =~ $re ]]` returns 2 for an invalid regex | all | the catalog reports an invalid `@whichkey-exclude` |
| `$(...)` strips trailing newlines | all | used on purpose in `popup.sh` to print the grid without its last newline |
