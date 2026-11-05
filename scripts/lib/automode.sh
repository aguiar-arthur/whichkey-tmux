# Auto mode plumbing shared by whichkey.tmux, auto.sh and popup.sh.
# Requires quote.sh.

WK_AUTO_SH="${BASH_SOURCE[0]%/lib/*}/auto.sh"

# What a key binding is likely to change: expanded when the prefix is pressed
# and again before showing the popup, to tell whether a key ran in between.
WK_STATE_FORMAT='#{session_id}:#{window_id}:#{pane_id}:#{window_layout}'

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

# While the prefix option is None, send-prefix sends nothing, so the prefix
# table gets a stand-in that sends the prefix key itself.

# bind_prefix_standin <prefix>
bind_prefix_standin() {
	tmux bind-key -N "Send the prefix key" -T prefix "$1" send-keys "$1"
}

# is_prefix_standin <prefix> <command>: <command> is our stand-in, as
# list-keys shows it.
is_prefix_standin() {
	[ "$2" = "send-keys $1" ]
}
