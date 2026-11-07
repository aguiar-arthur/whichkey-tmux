#!/usr/bin/env bash
# Opens the search: a popup that filters key bindings as you type (see
# search-popup.sh). It lists the prefix table, the groups reachable from it,
# and your own root-table bindings, each with the whole key sequence that
# reaches it ("C-b w n").
#
# Usage: search.sh <client> <pane>
#
# The bindings are read here, before the popup opens, and handed over in a
# file: one WK_SEP-separated line per binding, "table key keys label".

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/quote.sh
source "$CURRENT_DIR/lib/quote.sh"
# shellcheck source=lib/options.sh
source "$CURRENT_DIR/lib/options.sh"
# shellcheck source=lib/tmux.sh
source "$CURRENT_DIR/lib/tmux.sh"
# shellcheck source=lib/bindings.sh
source "$CURRENT_DIR/lib/bindings.sh"
# shellcheck source=lib/automode.sh
source "$CURRENT_DIR/lib/automode.sh"
# shellcheck source=lib/debug.sh
source "$CURRENT_DIR/lib/debug.sh"

debug_init "$@"

client=$1
pane=$2

# read_settings: the client size and every option, in one round-trip.
read_settings() {
	local prefix_option
	read_formats "$client" \
		width '#{client_width}' \
		height '#{client_height}' \
		version '#{version}' \
		exclude '#{@whichkey-exclude}' \
		label_width '#{@whichkey-label-width}' \
		key_style '#{@whichkey-key-style}' \
		border_lines '#{@whichkey-border-lines}' \
		prefix_option '#{prefix}' \
		prefix '#{@whichkey-prefix}' \
		prefix2 '#{@whichkey-prefix2}'
	WK_TMUX_VERSION=$version
	label_width=${label_width:-$WK_DEFAULT_LABEL_WIDTH}
	key_style=${key_style:-$WK_DEFAULT_KEY_STYLE}
	border_lines=${border_lines:-$WK_DEFAULT_BORDER_LINES}
	# In auto mode the prefix option is None and the key is saved.
	[ "$prefix_option" = None ] || prefix=$prefix_option
	# The catalog reports an invalid regex; here it just hides nothing.
	if [ -n "$exclude" ]; then
		[[ "" =~ $exclude ]]
		[ "$?" -ne 2 ] || exclude=
	fi
}

# collect <file>: write the searchable bindings to <file>, yours first.
# Tables are visited breadth first from prefix and root, each once; a group
# adds its table, reached by the keys that led to the group.
collect() {
	local tables=(prefix root) leads=("${prefix:-prefix} " '') seen=' prefix root '
	local t=0 table lead i key label line yours='' others=''
	while [ "$t" -lt "${#tables[@]}" ]; do
		table=${tables[$t]} lead=${leads[$t]}
		t=$((t + 1))
		load_bindings "$table"
		for ((i = 0; i < ${#WK_KEYS[@]}; i++)); do
			key=${WK_KEYS[$i]}
			# tmux's root bindings are the mouse and the like.
			[ "$table" != root ] || [ "${WK_IS_USER[$i]}" = 1 ] || continue
			# The plugin's own keys, and its stand-ins for send-prefix.
			case ${WK_COMMANDS[$i]} in *"$CURRENT_DIR/"*) continue ;; esac
			case $key in
			"$prefix" | "$prefix2") is_prefix_standin "$key" "${WK_COMMANDS[$i]}" && continue ;;
			esac
			is_excluded "$i" "$exclude" && continue
			if [ -n "${WK_GROUP[$i]}" ]; then
				case $seen in *" ${WK_GROUP[$i]} "*) continue ;; esac
				seen="$seen${WK_GROUP[$i]} "
				tables+=("${WK_GROUP[$i]}")
				leads+=("$lead$key ")
				continue
			fi
			binding_label label "$i"
			truncate_label label "$label" "$label_width" "…"
			line="$table$WK_SEP$key$WK_SEP$lead$key$WK_SEP$label"$'\n'
			if [ "${WK_IS_USER[$i]}" = 1 ]; then
				yours=$yours$line
			else
				others=$others$line
			fi
		done
	done
	printf '%s%s' "$yours" "$others" >"$1"
}

main() {
	local entries popup_width popup_height
	read_settings
	entries=$(mktemp "${TMPDIR:-/tmp}/whichkey.XXXXXX")
	collect "$entries"
	popup_width=100 popup_height=24
	[ "$popup_width" -le $((width - 4)) ] || popup_width=$((width - 4))
	[ "$popup_height" -le $((height - 4)) ] || popup_height=$((height - 4))
	[ "$popup_width" -ge 20 ] || popup_width=$width
	[ "$popup_height" -ge 5 ] || popup_height=$height
	# The border takes two rows and two columns.
	tmux display-popup -c "$client" -t "$pane" -E -b "$border_lines" -T " search " \
		-x C -y C -w "$popup_width" -h "$popup_height" \
		"$CURRENT_DIR/search-popup.sh" "$client" "$entries" \
		$((popup_height - 2)) $((popup_width - 2)) "$key_style" ||
		rm -f "$entries"
}

main
exit 0
