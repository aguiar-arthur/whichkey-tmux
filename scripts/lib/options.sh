# Defaults for every @whichkey-* option, in one place.

WK_DEFAULT_KEY=Space      # @whichkey-key
WK_DEFAULT_SEARCH_KEY=''  # @whichkey-search-key: none, the catalog has a Search item
WK_DEFAULT_X=C            # @whichkey-x
WK_DEFAULT_Y=S            # @whichkey-y
WK_DEFAULT_LABEL_WIDTH=40 # @whichkey-label-width
WK_DEFAULT_AUTO=off       # @whichkey-auto
WK_DEFAULT_DELAY=200      # @whichkey-delay, in milliseconds
WK_DEFAULT_DEBUG=off      # @whichkey-debug

# The auto popup.
WK_DEFAULT_KEY_STYLE='fg=magenta,bold' # @whichkey-key-style
WK_DEFAULT_GROUP_STYLE='fg=blue'       # @whichkey-group-style
WK_DEFAULT_BORDER_LINES=rounded        # @whichkey-border-lines
# @whichkey-popup-defaults: tmux's own bindings in the popup: "auto" when
# your config binds nothing in that table (a fresh install), "on" always
# (after yours), "off" never.
WK_DEFAULT_POPUP_DEFAULTS=auto

# @whichkey-exclude: unless set, these tmux defaults are hidden from the
# menu: window numbers, arrow-key variants and the M-1..M-5 layout presets,
# which crowd it without telling you anything new. Your own bindings are
# never hidden by this default.
WK_DEFAULT_EXCLUDE='^(M-)?[0-9]$|^(C-|M-|C-M-)?(Up|Down|Left|Right)$'
