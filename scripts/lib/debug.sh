# Debug log. With @whichkey-debug on, whichkey.tmux puts the log path in
# tmux's global environment as WHICHKEY_TMUX_DEBUG; run-shell and popups
# inherit it, and each script then traces itself into the log.

WK_DEBUG_LOG="${XDG_CACHE_HOME:-$HOME/.cache}/whichkey-tmux/debug.log"

# debug_init <args...>: if debugging, send stderr and an execution trace to
# the log. Call first thing, with the script's arguments.
debug_init() {
	[ -n "$WHICHKEY_TMUX_DEBUG" ] || return 0
	exec 2>>"$WHICHKEY_TMUX_DEBUG"
	printf '\n== %s %s %s\n' "$(date '+%F %T')" "${0##*/}" "$*" >&2
	PS4='+ ${BASH_SOURCE[0]##*/}:${LINENO} ${FUNCNAME[0]:-main}: '
	set -x
}
