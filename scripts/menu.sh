#!/usr/bin/env bash
# Show a which-key menu built from the live bindings of a key table.
#
# Usage: menu.sh <client> <pane> [table] [page]
#
# Each item replays its key with `send-keys -K`, so the original binding runs
# exactly as if typed: no command re-parsing, and -r (repeat) still works.
#
# The steps in main() share the script's settings and pass their results on
# in UPPERCASE arrays (bash 3.2 cannot return arrays).

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/quote.sh
source "$CURRENT_DIR/lib/quote.sh"
# shellcheck source=lib/options.sh
source "$CURRENT_DIR/lib/options.sh"
# shellcheck source=lib/tmux.sh
source "$CURRENT_DIR/lib/tmux.sh"
# shellcheck source=lib/bindings.sh
source "$CURRENT_DIR/lib/bindings.sh"
# shellcheck source=lib/keys.sh
source "$CURRENT_DIR/lib/keys.sh"
# shellcheck source=lib/layout.sh
source "$CURRENT_DIR/lib/layout.sh"

SELF="$CURRENT_DIR/menu.sh"

client=$1
pane=$2
table=${3:-prefix}
page=${4:-1}

# read_settings: the client size and every option, in one round-trip.
read_settings() {
	read_formats "$client" \
		height '#{client_height}' \
		exclude '#{@whichkey-exclude}' \
		pos_x '#{@whichkey-x}' \
		pos_y '#{@whichkey-y}' \
		label_width '#{@whichkey-label-width}' \
		version '#{version}'
	height=${height:-24}
	pos_x=${pos_x:-$WK_DEFAULT_X}
	pos_y=${pos_y:-$WK_DEFAULT_Y}
	label_width=${label_width:-$WK_DEFAULT_LABEL_WIDTH}
}

# menu_command <var> <client> <pane> <table> <page>: tmux command that opens
# this menu on another table or page.
menu_command() {
	local _self _client _pane _table _sh
	sh_quote _self "$SELF"
	sh_quote _client "$2"
	sh_quote _pane "$3"
	sh_quote _table "$4"
	format_escape _sh "$_self $_client $_pane $_table $5"
	tmux_quote _sh "$_sh"
	printf -v "$1" 'run-shell -b %s' "$_sh"
}

# key_command <var> <client> <table> <key>: tmux command that presses <key>
# in <table> on <client>.
key_command() {
	local _client _table _key _press
	tmux_quote _client "$2"
	if [ "$3" = root ]; then
		_press="send-keys -c $_client -K"
	else
		tmux_quote _table "$3"
		_press="switch-client -c $_client -T $_table ; send-keys -c $_client -K"
	fi
	if key_hex _key "$4"; then
		printf -v "$1" '%s -H %s' "$_press" "$_key"
	else
		tmux_quote _key "$4"
		printf -v "$1" '%s %s' "$_press" "$_key"
	fi
}

# is_shown <index>: hide this menu's own binding, tmux defaults that match
# the exclude pattern and, if @whichkey-exclude is set, your bindings that
# match it.
is_shown() {
	local key=${WK_KEYS[$1]}
	case ${WK_COMMANDS[$1]} in *"$SELF"*) return 1 ;; esac
	if [ "${WK_IS_USER[$1]}" = 1 ]; then
		[ -z "$exclude" ] || ! [[ $key =~ $exclude ]]
	else
		! [[ $key =~ ${exclude:-$WK_DEFAULT_EXCLUDE} ]]
	fi
}

# build_items: a menu item for each shown binding, as ITEM_LABELS, ITEM_KEYS,
# ITEM_COMMANDS and ITEM_IS_USER, escaped and ready for display-menu.
build_items() {
	local i key label command
	ITEM_LABELS=() ITEM_KEYS=() ITEM_COMMANDS=() ITEM_IS_USER=()
	for ((i = 0; i < ${#WK_KEYS[@]}; i++)); do
		is_shown "$i" || continue
		key=${WK_KEYS[$i]}

		binding_label label "$i"
		truncate_label label "$label" "$label_width" "…"
		# A leading hyphen would make tmux show the item as disabled.
		case $label in -*) label=" $label" ;; esac
		format_escape label "$label"
		argv_escape label "$label"

		if [ -n "${WK_GROUP[$i]}" ]; then
			menu_command command "$client" "$pane" "${WK_GROUP[$i]}" 1
		else
			key_command command "$client" "$table" "$key"
		fi
		format_escape command "$command"
		argv_escape key "$key"

		ITEM_LABELS+=("$label")
		ITEM_KEYS+=("$key")
		ITEM_COMMANDS+=("$command")
		ITEM_IS_USER+=("${WK_IS_USER[$i]}")
	done
}

# order_items: ORDER lists item indexes, your bindings first, then a
# separator (-1) and tmux's defaults.
order_items() {
	local want i
	ORDER=()
	for want in 1 0; do
		[ "$want" = 0 ] && [ "${#ORDER[@]}" -gt 0 ] && ORDER+=(-1)
		for ((i = 0; i < ${#ITEM_KEYS[@]}; i++)); do
			[ "${ITEM_IS_USER[$i]}" = "$want" ] && ORDER+=("$i")
		done
	done
	if [ "${#ORDER[@]}" -gt 0 ] && [ "${ORDER[${#ORDER[@]} - 1]}" = -1 ]; then
		unset "ORDER[${#ORDER[@]} - 1]"
	fi
}

# menu_args: display-menu arguments for the rows START..END of ORDER, plus
# page navigation. Sets ARGS.
menu_args() {
	local i n nav
	ARGS=()
	for ((i = START; i < END; i++)); do
		n=${ORDER[$i]}
		if [ "$n" = -1 ]; then
			# No separator at the edge of a page.
			[ "$i" -eq "$START" ] || [ "$i" -eq $((END - 1)) ] || ARGS+=("")
		else
			ARGS+=("${ITEM_LABELS[$n]}" "${ITEM_KEYS[$n]}" "${ITEM_COMMANDS[$n]}")
		fi
	done

	[ "$PAGES" -gt 1 ] || return 0
	ARGS+=("")
	if [ "$PAGE" -lt "$PAGES" ]; then
		menu_command nav "$client" "$pane" "$table" $((PAGE + 1))
		format_escape nav "$nav"
		ARGS+=("Next page" C-n "$nav")
	fi
	if [ "$PAGE" -gt 1 ]; then
		menu_command nav "$client" "$pane" "$table" $((PAGE - 1))
		format_escape nav "$nav"
		ARGS+=("Previous page" C-p "$nav")
	fi
}

show_menu() {
	local title
	format_escape title "$table"
	[ "$PAGES" -le 1 ] || title="$title ($PAGE/$PAGES)"
	tmux display-menu -c "$client" -t "$pane" -T "#[align=centre] $title " \
		-x "$pos_x" -y "$pos_y" "${ARGS[@]}"
}

main() {
	read_settings
	load_bindings "$table" "$version"
	build_items
	order_items
	if [ "${#ORDER[@]}" -eq 0 ]; then
		tmux display-message -c "$client" "whichkey: no bindings in table '$table'"
		return
	fi
	# Menus taller than the client are silently not drawn, so paginate.
	# Reserve rows for the border and the status line.
	paginate "${#ORDER[@]}" $((height - 4)) "$page"
	menu_args
	show_menu
}

main
exit 0
