# Auto mode plumbing shared by whichkey.tmux, auto.sh and popup.sh.
# Requires quote.sh.

WK_AUTO_SH="${BASH_SOURCE[0]%/lib/*}/auto.sh"

# What a key binding is likely to change: expanded when the prefix is pressed
# and again before showing the popup, to tell whether a key ran in between.
WK_STATE_FORMAT='#{session_id}:#{window_id}:#{pane_id}:#{window_layout}'

# Each prefix press bumps the global @whichkey-seq and copies it to
# @whichkey-seq-<client name>, so a press on one client does not cancel a
# popup pending on another. (tmux cannot nest formats, so the per-client
# option cannot be incremented directly.)

# seq_format <var> <client>: format for the client's sequence number.
seq_format() {
	printf -v "$1" '#{@whichkey-seq-%s}' "$2"
}

# The client-detached hook entry that removes a client's sequence option.
# A fixed, unusual index so it neither replaces nor is replaced by the
# user's own hooks.
WK_DETACH_HOOK='client-detached[7351]'

# ms_to_seconds <var> <ms>: as run-shell -d wants it, e.g. 200 -> 0.200.
ms_to_seconds() {
	printf -v "$1" '%d.%03d' $(($2 / 1000)) $(($2 % 1000))
}

# auto_command <var> <client> <pane> <seq>: shell command for run-shell that
# runs auto.sh. The arguments may be formats; WK_STATE_FORMAT always is, so
# the state is captured when run-shell runs, not after its delay.
auto_command() {
	local _auto _client _pane _seq
	sh_quote _auto "$WK_AUTO_SH"
	format_escape _auto "$_auto"
	sh_quote _client "$2"
	sh_quote _pane "$3"
	sh_quote _seq "$4"
	printf -v "$1" "%s %s %s %s '%s'" "$_auto" "$_client" "$_pane" "$_seq" "$WK_STATE_FORMAT"
}

# send_prefix_command <var> <option>: the binding that sends the key of
# <option> (prefix or prefix2), as list-keys shows it.
send_prefix_command() {
	case $2 in
	prefix2) printf -v "$1" 'send-prefix -2' ;;
	*) printf -v "$1" 'send-prefix' ;;
	esac
}

# While a prefix option is None, send-prefix sends nothing, so whichkey.tmux
# gives the prefix table a stand-in that sends the key itself.

# is_prefix_standin <key> <command>: <command> is our stand-in for <key>,
# as list-keys shows it.
is_prefix_standin() {
	[ "$2" = "send-keys $1" ]
}
