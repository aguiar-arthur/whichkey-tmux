# Defaults for every @whichkey-* option, in one place.

WK_DEFAULT_KEY=Space       # @whichkey-key
WK_DEFAULT_X=C             # @whichkey-x
WK_DEFAULT_Y=S             # @whichkey-y
WK_DEFAULT_LABEL_WIDTH=40  # @whichkey-label-width
WK_DEFAULT_AUTO=off        # @whichkey-auto
WK_DEFAULT_DELAY=200       # @whichkey-delay, in milliseconds
WK_DEFAULT_DEBUG=off       # @whichkey-debug

# @whichkey-exclude: unless set, these tmux defaults are hidden from the
# menu: window numbers, arrow-key variants and the M-1..M-5 layout presets,
# which crowd it without telling you anything new. Your own bindings are
# never hidden by this default.
WK_DEFAULT_EXCLUDE='^(M-)?[0-9]$|^(C-|M-|C-M-)?(Up|Down|Left|Right)$'
