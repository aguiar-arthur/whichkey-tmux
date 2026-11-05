# Debug log. With @whichkey-debug on, whichkey.tmux creates WK_DEBUG_FLAG,
# and every script then traces itself into WK_DEBUG_LOG. A file rather than
# an environment variable: on tmux 3.4, run-shell jobs did not see a
# variable set with set-environment after the server started.

WK_DEBUG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/whichkey-tmux"
WK_DEBUG_FLAG="$WK_DEBUG_DIR/debug.on"
WK_DEBUG_LOG="$WK_DEBUG_DIR/debug.log"

# debug_init <args...>: if debugging, send stderr and an execution trace to
# the log. Call first thing, with the script's arguments.
debug_init() {
	[ -e "$WK_DEBUG_FLAG" ] || return 0
	exec 2>>"$WK_DEBUG_LOG"
	printf '\n== %s %s %s\n' "$(date '+%F %T')" "${0##*/}" "$*" >&2
	PS4='+ ${BASH_SOURCE[0]##*/}:${LINENO} ${FUNCNAME[0]:-main}: '
	set -x
}
