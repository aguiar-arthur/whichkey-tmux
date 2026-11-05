#!/usr/bin/env bash
# Runs inside the auto popup: shows the grid, reads one key and hands it to
# the key table, so every key works, including ones not listed.
#
# Usage: popup.sh <client> <pane> <table> <content-file> <seq> <delay-ms> <group-keys>
#
# <group-keys> is a space-separated list (with leading and trailing spaces) of
# keys that switch to another table; choosing one schedules auto.sh again so
# that table gets its own popup after the delay.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/quote.sh
source "$CURRENT_DIR/lib/quote.sh"
# shellcheck source=lib/keys.sh
source "$CURRENT_DIR/lib/keys.sh"
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

# show_content: raw input before drawing anything, so a key typed the moment
# the popup appears is neither echoed nor held back waiting for Enter. opost
# keeps newlines in the grid working.
show_content() {
	stty raw -echo opost min 1 time 0
	printf '\e[?25l'
	cat "$content"
	rm -f "$content"
}

# One raw byte as two hex digits. stty min/time control how long dd waits.
read_byte() {
	dd bs=1 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n'
}

# read_key <var>: wait for one key and set <var> to its tmux name.
read_key() {
	local _byte _rest=
	_byte=$(read_byte)
	if needs_rest "$_byte"; then
		# The rest of an escape sequence or character arrives within a
		# tenth of a second; a lone Escape gets nothing more.
		stty min 0 time 1
		_rest=$(dd bs=16 count=1 2>/dev/null)
	fi
	decode_key "$1" "$_byte" "$_rest"
}

# forward_key <key>: close the popup first, so the key reaches the key table
# rather than the popup, then press it there. A group key also schedules
# auto.sh after the delay, like the prefix key does.
forward_key() {
	local key=$1 hex seconds run send follow=()
	case $group_keys in
	*" $key "*)
		ms_to_seconds seconds "$delay"
		auto_command run "$client" "$pane" "$seq"
		follow=(\; run-shell -b -d "$seconds" -t "$pane" "$run")
		;;
	esac
	if key_hex hex "$key"; then
		send=(-H "$hex")
	else
		# Named keys only need a trailing ";" escaped (M-;).
		argv_escape key "$key"
		send=("$key")
	fi
	tmux display-popup -C -c "$client" \; switch-client -c "$client" -T "$table" \
		\; send-keys -c "$client" -K "${send[@]}" "${follow[@]}"
}

main() {
	local key
	show_content
	read_key key
	if [ -z "$key" ]; then
		tmux display-popup -C -c "$client" \; switch-client -c "$client" -T root
		return
	fi
	forward_key "$key"
}

main
