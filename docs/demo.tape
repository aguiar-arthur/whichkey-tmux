# Records docs/demo.gif with vhs (https://github.com/charmbracelet/vhs).
# Run from the repository root: vhs docs/demo.tape
# CI does this on demand: the "Demo" workflow.

Output docs/demo.gif
Require tmux

Set Shell bash
Set FontSize 18
Set Width 1200
Set Height 640
Set Padding 16
Set Theme "Dracula"
Set TypingSpeed 120ms

Hide
Type "PS1='$ ' tmux -L demo -f docs/demo.conf new -s demo" Enter
Sleep 2s
Type "clear" Enter
Sleep 500ms
Show

# Press the prefix and wait: your bindings pop up.
Sleep 1s
Ctrl+B
Sleep 2.5s
Type "|"
Sleep 1.5s

# Groups get their own popup.
Ctrl+B
Sleep 1.5s
Type "w"
Sleep 2.5s
Type "n"
Sleep 1.5s

# Typing at full speed never shows the popup.
Ctrl+B
Type "-"
Sleep 1.5s

# prefix Space: the full catalog, your bindings first.
Ctrl+B
Type " "
Sleep 2.5s
Down@300ms 4
Sleep 1s
Escape
Sleep 1s

Hide
Type "tmux -L demo kill-server" Enter
