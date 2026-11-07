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
Type "tmux -L demo -f docs/demo.conf new -s demo" Enter
Sleep 2s
Type "clear" Enter
Sleep 500ms
Show

# Press the prefix and wait: your bindings pop up.
Sleep 1s
Ctrl+B
Sleep 2.5s
Screenshot docs/shots/popup.png
Type "|"
Sleep 1.5s

# Groups get their own popup; Backspace goes back up.
Ctrl+B
Sleep 1.5s
Type "w"
Sleep 2.5s
Screenshot docs/shots/group.png
Backspace
Sleep 1.5s
Type "w"
Sleep 1s
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
Screenshot docs/shots/catalog.png
Escape
Sleep 1s

# prefix /: search every binding as you type.
Ctrl+B
Type "/"
Sleep 1.5s
Type "win"
Sleep 1s
Down
Sleep 1.5s
Screenshot docs/shots/search.png
Escape
Sleep 1s

Hide
Type "tmux -L demo kill-server" Enter
