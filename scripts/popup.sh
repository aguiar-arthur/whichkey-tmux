#!/usr/bin/env bash
# Runs inside the auto popup: shows the grid, reads one key and hands it to
# the key table, so every key works, including ones not listed.
#
# Usage: popup.sh <client> <pane> <table> <content-file> <seq> <delay-ms>
#                 <group-keys> <path> <back>
#
# <group-keys> is a space-separated list (with leading and trailing spaces) of
# keys that switch to another table; choosing one schedules auto.sh again so
# that table gets its own popup after the delay. <path> lists the tables
# above this one (see auto.sh). <back> is 1 if BSpace goes back to the table
# above: there is one, and this table does not bind BSpace itself.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/quote.sh
source "$CURRENT_DIR/lib/quote.sh"
# shellcheck source=lib/keys.sh
source "$CURRENT_DIR/lib/keys.sh"
# shellcheck source=lib/input.sh
source "$CURRENT_DIR/lib/input.sh"
# shellcheck source=lib/automode.sh
source "$CURRENT_DIR/lib/automode.sh"
# shellcheck source=lib/debug.sh
source "$CURRENT_DIR/lib/debug.sh"

debug_init "$@"

client=$1
pane=$2
table=$3
content=$4
seq=$5
delay=$6
group_keys=$7
path=$8
back=$9

# show_content: raw input before drawing anything, so a key typed the moment
# the popup appears is neither echoed nor held back waiting for Enter.
show_content() {
	raw_input
	# No newline after the last row: at the bottom of the popup it would
	# scroll the first row out of sight.
	printf '\e[?25l%s' "$(<"$content")"
	rm -f "$content"
}

# forward_key <key>: close the popup first, so the key reaches the key table
# rather than the popup, then press it there. A group key also schedules
# auto.sh after the delay, like the prefix key does, one level deeper.
forward_key() {
	local key=$1 seconds run follow=()
	case $group_keys in
	*" $key "*)
		ms_to_seconds seconds "$delay"
		auto_command run "$client" "$pane" "$seq" "${path:+$path }$table"
		follow=(\; run-shell -b -d "$seconds" -t "$pane" "$run")
		;;
	esac
	press_args "$client" "$table" "$key"
	tmux display-popup -C -c "$client" \; "${PRESS[@]}" "${follow[@]}"
}

# go_back: show the popup of the table above this one, at once.
go_back() {
	local parent=${path##* } above='' run
	case $path in *" "*) above=${path% *} ;; esac
	auto_command run "$client" "$pane" "$seq" "$above"
	tmux display-popup -C -c "$client" \; switch-client -c "$client" -T "$parent" \
		\; run-shell -b -t "$pane" "$run"
}

main() {
	local key
	show_content
	read_key key
	if [ -z "$key" ]; then
		tmux display-popup -C -c "$client" \; switch-client -c "$client" -T root
	elif [ "$key" = BSpace ] && [ "$back" = 1 ]; then
		go_back
	else
		forward_key "$key"
	fi
}

main
