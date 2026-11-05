# Debug log. With @whichkey-debug on, whichkey.tmux creates WK_DEBUG_FLAG,
# and every script then traces itself into WK_DEBUG_LOG. Checking for a file
# costs no tmux call, so scripts can test it before doing anything else.

WK_DEBUG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/whichkey-tmux"
WK_DEBUG_FLAG="$WK_DEBUG_DIR/debug.on"
WK_DEBUG_LOG="$WK_DEBUG_DIR/debug.log"

# debug_init <args...>: if debugging, send stderr and an execution trace to
# the log. Call first thing, with the script's arguments.
debug_init() {
	[ -e "$WK_DEBUG_FLAG" ] || return 0
	# The trace shows the commands of the user's bindings: keep it private.
	[ -e "$WK_DEBUG_LOG" ] || (umask 077 && : >>"$WK_DEBUG_LOG")
	exec 2>>"$WK_DEBUG_LOG"
	printf '\n== %s %s %s\n' "$(date '+%F %T')" "${0##*/}" "$*" >&2
	PS4='+ ${BASH_SOURCE[0]##*/}:${LINENO} ${FUNCNAME[0]:-main}: '
	set -x
}
