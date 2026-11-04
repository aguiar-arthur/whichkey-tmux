# whichkey-tmux

A which-key menu for tmux, built from the bindings you **already have**.
No YAML and no build step: it reads `tmux list-keys` every time it opens, so
the menu always matches your config.

- Labels come from binding notes (`bind -N "Lazygit" G ...`), falling back to
  the command itself.
- Choosing an item replays the key with `send-keys -K`, so the binding runs
  exactly as if you typed it, including `-r` repeat bindings.
- Keys that switch to another key table (`bind g switch-client -T git`) show
  as `+groups` and open a submenu for that table.
- Your own bindings come first, then tmux's defaults after a separator, so
  what you configured is always on page 1.
- Long menus are paginated (`C-n` / `C-p`) instead of silently failing to draw.

Requires tmux 3.4+ and bash (3.2 is fine).

## Install

With [TPM](https://github.com/tmux-plugins/tpm):

```tmux
set -g @plugin 'aguiar-arthur/whichkey-tmux'
```

Or manually, at the end of `tmux.conf`:

```tmux
run-shell ~/path/to/whichkey-tmux/whichkey.tmux
```

Then press `prefix Space`.

## Auto popup (optional)

Like which-key in Neovim: press the prefix, pause, and a popup lists the
bindings **your config defines** (tmux's ~90 defaults are left out). Any key,
listed or not, goes straight through to tmux, so typing at full speed never
shows the popup and nothing changes. `prefix Space` stays the full catalog.
Keys that switch to another key table get their own popup the same way.

```tmux
set -g @whichkey-auto on
set -g @whichkey-delay 200   # ms to wait before showing the popup
```

How it works: tmux handles the prefix internally, with no hook to attach a
timer to. So auto mode sets `prefix None` and binds your prefix key itself
(root and copy-mode tables) to switch to the prefix table and check back after
the delay. `#{client_prefix}` keeps working. Turning the option off and
reloading restores the prefix.

tmux has no "a key was pressed" signal either, and after a repeat (`-r`)
binding such as `bind -r H resize-pane -L` the client stays in the prefix
table. So the popup only shows if the session, window, active pane and layout
are unchanged since the prefix: a repeat binding that changes none of these
could still let the popup appear.

"Your bindings" means bindings that differ from a config-less tmux; the
built-in list is read once per tmux version and cached in
`~/.cache/whichkey-tmux`.

## Better labels

Give your bindings notes; they show up in the menu and in `prefix ?`:

```tmux
bind -N "Lazygit" G display-popup -E lazygit
```

## Options

| Option | Default | |
|---|---|---|
| `@whichkey-key` | `Space` | Key in the prefix table that opens the menu |
| `@whichkey-root-key` | unset | Key in the root table (no prefix), e.g. `M-Space` |
| `@whichkey-exclude` | tmux's digit, arrow and `M-1`..`M-5` bindings | Extended regex of keys to hide in the menu (the default never hides your own bindings); `'^$'` shows everything |
| `@whichkey-x` / `@whichkey-y` | `C` / `S` | Menu position, as in `display-menu -x/-y` |
| `@whichkey-label-width` | `40` | Truncate labels longer than this |
| `@whichkey-auto` | `off` | Show the popup after a pause on the prefix |
| `@whichkey-delay` | `200` | Milliseconds to wait before the auto popup |

## Tests

```sh
tests/e2e.sh
```

Starts a private tmux server with a real attached client (macOS `script`),
drives the menu and the auto popup with simulated keypresses and checks the
bindings fire.
