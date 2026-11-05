#!/usr/bin/env bash
# Run after @whichkey-delay, once by the prefix key and again after a group
# key chosen in the popup. If the client is still waiting in a key table and
# nothing happened since, pop up the bindings your config defines there,
# laid out in columns.
#
# Usage: auto.sh <client> <pane> <seq> <state>
#
# <seq> is the client's sequence number (see lib/automode.sh) when the prefix
# was pressed; a newer prefix press on the same client cancels this run. <state> is WK_STATE_FORMAT expanded at the same moment.
# tmux has no "a key was pressed" signal, and after a repeat (-r) binding the
# client stays in the prefix table, so a changed state is how we tell that a
# key did something (resized, moved to another pane or window...).
#
# The steps in main() share the script's settings and pass their results on
# in UPPERCASE variables (bash 3.2 cannot return arrays).

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/quote.sh
source "$CURRENT_DIR/lib/quote.sh"
# shellcheck source=lib/options.sh
source "$CURRENT_DIR/lib/options.sh"
# shellcheck source=lib/tmux.sh
source "$CURRENT_DIR/lib/tmux.sh"
# shellcheck source=lib/bindings.sh
source "$CURRENT_DIR/lib/bindings.sh"
# shellcheck source=lib/layout.sh
source "$CURRENT_DIR/lib/layout.sh"
# shellcheck source=lib/automode.sh
source "$CURRENT_DIR/lib/automode.sh"
# shellcheck source=lib/style.sh
source "$CURRENT_DIR/lib/style.sh"
# shellcheck source=lib/debug.sh
source "$CURRENT_DIR/lib/debug.sh"

debug_init "$@"

client=$1
pane=$2
seq=$3
state=$4

# Space between columns.
GAP=4

# still_waiting <var>: sets <var> to the client's key table and succeeds if
# the popup should still be shown: the client is in a table other than root,
# with no newer prefix press and no change of state.
still_waiting() {
	local _table _seq _state _seq_format
	seq_format _seq_format "$client"
	read_formats "$client" _table '#{client_key_table}' _seq "$_seq_format" _state "$WK_STATE_FORMAT"
	printf -v "$1" '%s' "$_table"
	[ "$_table" != root ] && [ "$_seq" = "$seq" ] && [ "$_state" = "$state" ]
}

# read_settings: the client size and every option, in one round-trip.
read_settings() {
	read_formats "$client" \
		width '#{client_width}' \
		height '#{client_height}' \
		version '#{version}' \
		prefix '#{@whichkey-prefix}' \
		prefix2 '#{@whichkey-prefix2}' \
		label_width '#{@whichkey-label-width}' \
		delay '#{@whichkey-delay}' \
		key_style '#{@whichkey-key-style}' \
		group_style '#{@whichkey-group-style}' \
		border_lines '#{@whichkey-border-lines}'
	WK_TMUX_VERSION=$version
	label_width=${label_width:-$WK_DEFAULT_LABEL_WIDTH}
	delay=${delay:-$WK_DEFAULT_DELAY}
	border_lines=${border_lines:-$WK_DEFAULT_BORDER_LINES}
	style_sgr key_sgr "${key_style:-$WK_DEFAULT_KEY_STYLE}"
	style_sgr group_sgr "${group_style:-$WK_DEFAULT_GROUP_STYLE}"
}

# select_cells: one cell per binding your config defines, as CELL_KEYS,
# CELL_LABELS and CELL_IS_GROUP; their widest key and label as KEY_WIDTH and
# TEXT_WIDTH; and GROUP_KEYS, the group keys as a space-separated list with
# leading and trailing spaces. Fails if there are none.
select_cells() {
	local i key label
	CELL_KEYS=() CELL_LABELS=() CELL_IS_GROUP=()
	GROUP_KEYS=" " KEY_WIDTH=0 TEXT_WIDTH=0
	for ((i = 0; i < ${#WK_KEYS[@]}; i++)); do
		[ "${WK_IS_USER[$i]}" = 1 ] || continue
		key=${WK_KEYS[$i]}
		# Our stand-ins for send-prefix (see whichkey.tmux) are plumbing.
		case $key in
		"$prefix" | "$prefix2") is_prefix_standin "$key" "${WK_COMMANDS[$i]}" && continue ;;
		esac

		binding_label label "$i"
		truncate_label label "$label" "$label_width" "…"
		if [ -n "${WK_GROUP[$i]}" ]; then
			CELL_IS_GROUP+=(1)
			GROUP_KEYS="$GROUP_KEYS$key "
		else
			CELL_IS_GROUP+=(0)
		fi
		CELL_KEYS+=("$key")
		CELL_LABELS+=("$label")
		[ "${#key}" -le "$KEY_WIDTH" ] || KEY_WIDTH=${#key}
		[ "${#label}" -le "$TEXT_WIDTH" ] || TEXT_WIDTH=${#label}
	done
	[ "${#CELL_KEYS[@]}" -gt 0 ]
}

# render_grid: print the grid laid out by grid_layout, each cell as
# "key → label", with one space of padding.
render_grid() {
	local r c i line color key label total=${#CELL_KEYS[@]}
	local dim=$'\e[2m' reset=$'\e[0m'
	for ((r = 0; r < ROWS; r++)); do
		line=" "
		for ((c = 0; c < COLS; c++)); do
			i=$((c * ROWS + r))
			[ "$c" -eq 0 ] || [ "$i" -gt "$SHOWN" ] || printf -v line '%s%*s' "$line" "$GAP" ''
			if [ "$i" -lt "$SHOWN" ]; then
				color=$reset
				[ "${CELL_IS_GROUP[$i]}" = 1 ] && color=$group_sgr
				# Pad by hand: printf pads by bytes, which misaligns
				# multibyte characters such as accented letters.
				key=${CELL_KEYS[$i]} label=${CELL_LABELS[$i]}
				printf -v line '%s%*s%s%s%s %s→%s %s%s%s%*s' "$line" \
					$((KEY_WIDTH - ${#key})) '' "$key_sgr" "$key" "$reset" \
					"$dim" "$reset" "$color" "$label" "$reset" $((TEXT_WIDTH - ${#label})) ''
			elif [ "$i" -eq "$SHOWN" ] && [ "$SHOWN" -lt "$total" ]; then
				printf -v line '%s%s… %d more%s' "$line" "$dim" $((total - SHOWN)) "$reset"
			fi
		done
		printf '%s\n' "$line"
	done
}

# show_popup <content-file>: draw the grid, if nothing happened while it was
# being built. popup.sh removes the file once it has shown it.
show_popup() {
	local now popup_width title
	# A key pressed while we were building the grid already ran its binding.
	if ! still_waiting now || [ "$now" != "$table" ]; then
		rm -f "$1"
		return
	fi
	popup_width=$((COLS * CELL + (COLS - 1) * GAP + 4))
	# The title is a format: a "#" in the table name must stay literal.
	format_escape title " $table "
	[ "$popup_width" -le "$width" ] || popup_width=$width
	tmux display-popup -c "$client" -t "$pane" -E -b "$border_lines" -T "$title" \
		-x C -y S -w "$popup_width" -h $((ROWS + 2)) \
		"$CURRENT_DIR/popup.sh" "$client" "$pane" "$table" "$1" \
		"$seq" "$delay" "$GROUP_KEYS" ||
		rm -f "$1"
}

main() {
	local max_rows content
	still_waiting table || return
	read_settings
	load_bindings "$table"
	select_cells || return

	CELL=$((KEY_WIDTH + 3 + TEXT_WIDTH))
	max_rows=$((height - 4))
	[ "$max_rows" -ge 1 ] || max_rows=1
	# The popup's border and padding take 4 columns.
	grid_layout "${#CELL_KEYS[@]}" "$CELL" "$GAP" $((width - 4)) "$max_rows"

	content=$(mktemp "${TMPDIR:-/tmp}/whichkey.XXXXXX")
	render_grid >"$content"
	show_popup "$content"
}

main
exit 0
