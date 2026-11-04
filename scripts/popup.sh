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
# shellcheck source=helpers.sh
source "$CURRENT_DIR/helpers.sh"

client=$1
pane=$2
table=$3
content=$4
seq=$5
delay=$6
group_keys=$7

# Raw input before drawing anything, so a key typed the moment the popup
# appears is neither echoed nor held back waiting for Enter. opost keeps
# newlines in the grid working.
stty raw -echo opost min 1 time 0
printf '\e[?25l'
cat "$content"
rm -f "$content"

# One raw byte as two hex digits. stty min/time control how long dd waits.
read_byte() {
	dd bs=1 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n'
}

byte=$(read_byte)

# Translate terminal input into a tmux key name.
key=
case $byte in
1b)
	# A lone Escape closes; otherwise read the rest of the sequence, which
	# arrives within a tenth of a second.
	stty min 0 time 1
	rest=$(dd bs=16 count=1 2>/dev/null)
	case $rest in
	'') key= ;;
	\[A | OA) key=Up ;;
	\[B | OB) key=Down ;;
	\[C | OC) key=Right ;;
	\[D | OD) key=Left ;;
	\[H | OH) key=Home ;;
	\[F | OF) key=End ;;
	\[5~) key=PPage ;;
	\[6~) key=NPage ;;
	\[2~) key=IC ;;
	\[3~) key=DC ;;
	\[Z) key=BTab ;;
	\[1\;[2-8][ABCD])
		case ${rest:3:1} in
		2) mod=S- ;; 3) mod=M- ;; 4) mod=S-M- ;; 5) mod=C- ;;
		6) mod=C-S- ;; 7) mod=C-M- ;; 8) mod=C-S-M- ;;
		esac
		case ${rest:4:1} in
		A) key=${mod}Up ;; B) key=${mod}Down ;; C) key=${mod}Right ;; D) key=${mod}Left ;;
		esac
		;;
	?) key="M-$rest" ;;
	esac
	;;
0d) key=Enter ;;
09) key=Tab ;;
7f) key=BSpace ;;
20) key=Space ;;
00) key=C-Space ;;
1c) key='C-\' ;;
1d) key='C-]' ;;
1e) key='C-^' ;;
1f) key=C-_ ;;
0[1-9a-f] | 1[0-9a])
	# Control characters 0x01-0x1a are C-a..C-z.
	letters=abcdefghijklmnopqrstuvwxyz
	key="C-${letters:$((16#$byte - 1)):1}"
	;;
[2-7][0-9a-f]) printf -v key "\\x$byte" ;;
esac

if [ -z "$key" ]; then
	tmux display-popup -C -c "$client" \; switch-client -c "$client" -T root
	exit 0
fi

# A group key: check back after the delay, like the prefix key does.
follow=()
case $group_keys in
*" $key "*)
	sh_quote q_auto "$CURRENT_DIR/auto.sh"
	sh_quote q_client "$client"
	sh_quote q_pane "$pane"
	sh_quote q_seq "$seq"
	printf -v seconds '%d.%03d' $((delay / 1000)) $((delay % 1000))
	format_escape q_auto "$q_auto"
	follow=(\; run-shell -b -d "$seconds" -t "$pane" "$q_auto $q_client $q_pane $q_seq '$WK_STATE_FORMAT'")
	;;
esac

# Single characters go as hex: the tmux CLI gives ";" and "{" special meaning
# as bare arguments. Named keys only need a trailing ";" escaped (M-;).
if [ "${#key}" -eq 1 ]; then
	send=(-H "$byte")
else
	argv_escape key "$key"
	send=("$key")
fi

# Close the popup first so the key reaches the key table, not the popup.
tmux display-popup -C -c "$client" \; switch-client -c "$client" -T "$table" \
	\; send-keys -c "$client" -K "${send[@]}" "${follow[@]}"
