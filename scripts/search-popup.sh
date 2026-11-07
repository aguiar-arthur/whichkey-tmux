#!/usr/bin/env bash
# Runs inside the search popup: a prompt, and the bindings that match what
# is typed, best first. Enter presses the selected binding's key, exactly as
# if typed; Escape closes.
#
# Usage: search-popup.sh <client> <entries-file> <rows> <cols> <key-style>
#
# <entries-file> comes from search.sh, which removes it if the popup never
# opens; this script removes it once read. <rows> and <cols> are the size
# inside the border.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/quote.sh
source "$CURRENT_DIR/lib/quote.sh"
# shellcheck source=lib/tmux.sh
source "$CURRENT_DIR/lib/tmux.sh"
# shellcheck source=lib/keys.sh
source "$CURRENT_DIR/lib/keys.sh"
# shellcheck source=lib/input.sh
source "$CURRENT_DIR/lib/input.sh"
# shellcheck source=lib/match.sh
source "$CURRENT_DIR/lib/match.sh"
# shellcheck source=lib/layout.sh
source "$CURRENT_DIR/lib/layout.sh"
# shellcheck source=lib/style.sh
source "$CURRENT_DIR/lib/style.sh"
# shellcheck source=lib/debug.sh
source "$CURRENT_DIR/lib/debug.sh"

debug_init "$@"

client=$1
entries=$2
rows=$3
cols=$4
style_sgr key_sgr "$5"

DIM=$'\e[2m'
REVERSE=$'\e[7m'
RESET=$'\e[0m'

# The prompt takes the first row and the hints the last.
VISIBLE=$((rows - 2))
[ "$VISIBLE" -ge 1 ] || VISIBLE=1

# load_entries: read the entries file into E_TABLES, E_KEYS (the key in its
# table), E_SEQUENCES (every key that leads there, "C-b w n") and E_LABELS,
# with SEQUENCE_WIDTH, the widest sequence.
load_entries() {
	local table key sequence label
	E_TABLES=() E_KEYS=() E_SEQUENCES=() E_LABELS=() SEQUENCE_WIDTH=0
	while IFS=$WK_SEP read -r table key sequence label; do
		[ -n "$key" ] || continue
		E_TABLES+=("$table")
		E_KEYS+=("$key")
		E_SEQUENCES+=("$sequence")
		E_LABELS+=("$label")
		[ "${#sequence}" -le "$SEQUENCE_WIDTH" ] || SEQUENCE_WIDTH=${#sequence}
	done <"$entries"
	rm -f "$entries"
}

# filter: MATCHES, the indexes of the entries that match QUERY: those that
# contain it first, then those that contain its characters in order.
filter() {
	local i rank pattern later=()
	MATCHES=()
	SELECTED=0 TOP=0
	fuzzy_pattern pattern "$QUERY"
	for ((i = 0; i < ${#E_KEYS[@]}; i++)); do
		match_rank rank "${E_SEQUENCES[$i]} ${E_LABELS[$i]}" "$QUERY" "$pattern"
		case $rank in
		0) MATCHES+=("$i") ;;
		1) later+=("$i") ;;
		esac
	done
	MATCHES+=("${later[@]}")
}

# move <rows>: move the selection by <rows>, within the matches.
move() {
	SELECTED=$((SELECTED + $1))
	[ "$SELECTED" -lt "${#MATCHES[@]}" ] || SELECTED=$((${#MATCHES[@]} - 1))
	[ "$SELECTED" -ge 0 ] || SELECTED=0
}

# entry_row <var> <index> <selected>: entry <index> as one row of the list,
# cut to the width, highlighted if <selected> is 1.
entry_row() {
	local _sequence=${E_SEQUENCES[$2]} _label _room _width=$((cols - 1))
	_room=$((_width - SEQUENCE_WIDTH - 3))
	[ "$_room" -ge 1 ] || _room=1
	truncate_label _label "${E_LABELS[$2]}" "$_room" "…"
	# Pad by hand: printf pads by bytes, which misaligns multibyte text.
	if [ "$3" = 1 ]; then
		printf -v "$1" '%s %s%*s  %s%*s%s' "$REVERSE" "$_sequence" \
			$((SEQUENCE_WIDTH - ${#_sequence})) '' "$_label" \
			$((_room - ${#_label})) '' "$RESET"
	else
		printf -v "$1" ' %s%s%s%*s  %s' "$key_sgr" "$_sequence" "$RESET" \
			$((SEQUENCE_WIDTH - ${#_sequence})) '' "$_label"
	fi
}

# render: draw the prompt, the visible matches and the hints in one write,
# then put the cursor at the end of the query.
render() {
	local frame row n line selected
	scroll_top TOP "$SELECTED" "$TOP" "$VISIBLE"
	frame=$'\e[H\e[2J'"${key_sgr}›${RESET} $QUERY"$'\n'
	for ((row = 0; row < VISIBLE; row++)); do
		n=$((TOP + row))
		if [ "$n" -lt "${#MATCHES[@]}" ]; then
			selected=0
			[ "$n" -ne "$SELECTED" ] || selected=1
			entry_row line "${MATCHES[$n]}" "$selected"
			frame="$frame$line"
		elif [ "$row" -eq 0 ]; then
			frame="$frame $DIM""no match$RESET"
		fi
		frame="$frame"$'\n'
	done
	# No newline after the last row: it would scroll the prompt away.
	frame="$frame$DIM ↑↓ select · enter run · esc close · ${#MATCHES[@]}/${#E_KEYS[@]}$RESET"
	printf '%s\e[1;%dH' "$frame" $((3 + ${#QUERY}))
}

# run_selected: close the popup, then press the selected binding's key in
# its table.
run_selected() {
	local i
	[ "${#MATCHES[@]}" -gt 0 ] || return
	i=${MATCHES[$SELECTED]}
	press_args "$client" "${E_TABLES[$i]}" "${E_KEYS[$i]}"
	tmux display-popup -C -c "$client" \; "${PRESS[@]}"
}

main() {
	local key
	raw_input
	load_entries
	QUERY=''
	filter
	render
	while :; do
		read_key key
		case $key in
		'' | C-c | C-g) return ;;
		Enter)
			run_selected
			return
			;;
		Up | C-p | C-k) move -1 ;;
		Down | C-n | C-j | Tab) move 1 ;;
		PPage) move $((-VISIBLE)) ;;
		NPage) move "$VISIBLE" ;;
		BSpace | C-h)
			QUERY=${QUERY%?}
			filter
			;;
		C-u)
			QUERY=''
			filter
			;;
		Space)
			QUERY="$QUERY "
			filter
			;;
		*)
			# A printable character; other keys do nothing here.
			[ "${#key}" -eq 1 ] || continue
			QUERY=$QUERY$key
			filter
			;;
		esac
		render
	done
}

main
exit 0
