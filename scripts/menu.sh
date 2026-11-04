#!/usr/bin/env bash
# Show a which-key menu built from the live bindings of a key table.
#
# Usage: menu.sh <client> <pane> [table] [page]
#
# Each item replays its key with `send-keys -K`, so the original binding runs
# exactly as if typed: no command re-parsing, and -r (repeat) still works.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
source "$CURRENT_DIR/helpers.sh"

client=$1
pane=$2
table=${3:-prefix}
page=${4:-1}
self="$CURRENT_DIR/menu.sh"

# Unless @whichkey-exclude is set, these tmux defaults are hidden: window
# numbers, arrow-key variants and the M-1..M-5 layout presets, which crowd the
# menu without telling you anything new. Your own bindings are never hidden.
default_exclude='^(M-)?[0-9]$|^(C-|M-|C-M-)?(Up|Down|Left|Right)$'

# One round-trip for the client size and every option we need.
IFS=$WK_SEP read -r height exclude pos_x pos_y label_width version <<EOF
$(tmux display-message -p -c "$client" "#{client_height}$WK_SEP#{@whichkey-exclude}$WK_SEP#{@whichkey-x}$WK_SEP#{@whichkey-y}$WK_SEP#{@whichkey-label-width}$WK_SEP#{version}")
EOF
pos_x=${pos_x:-C}
pos_y=${pos_y:-S}
label_width=${label_width:-40}

tmux_quote q_client "$client"
tmux_quote q_table "$table"
if [ "$table" = root ]; then
	press_prefix="send-keys -c $q_client -K"
else
	press_prefix="switch-client -c $q_client -T $q_table ; send-keys -c $q_client -K"
fi

# menu_command <var> <table> <page>: tmux command that reopens this menu.
menu_command() {
	local s1 s2 s3 s4 sh
	sh_quote s1 "$self"
	sh_quote s2 "$client"
	sh_quote s3 "$pane"
	sh_quote s4 "$2"
	format_escape sh "$s1 $s2 $s3 $s4 $3"
	tmux_quote sh "$sh"
	printf -v "$1" 'run-shell -b %s' "$sh"
}

group_re='^switch-client -T ([^ ]+)$'
load_defaults defaults "$version" "$table"

keys=()
labels=()
commands=()
is_user=()
while IFS= read -r line; do
	IFS=$WK_SEP read -r key note command <<<"$line"
	[ -n "$key" ] || continue
	case $command in *"$self"*) continue ;; esac
	case $defaults in
	*"
$line
"*)
		user=0
		[[ $key =~ ${exclude:-$default_exclude} ]] && continue
		;;
	*)
		user=1
		[ -n "$exclude" ] && [[ $key =~ $exclude ]] && continue
		;;
	esac

	if [[ $command =~ $group_re ]]; then
		label="+${note:-${BASH_REMATCH[1]}}"
		menu_command item_command "${BASH_REMATCH[1]}" 1
	else
		label=${note:-$command}
		# Send single ASCII characters as hex: punctuation such as ; or "
		# cannot be quoted reliably for the tmux command parser.
		printf -v code '%d' "'$key"
		if [ "${#key}" -eq 1 ] && [ "$code" -lt 128 ]; then
			printf -v item_command '%s -H %02x' "$press_prefix" "$code"
		else
			tmux_quote q_key "$key"
			item_command="$press_prefix $q_key"
		fi
	fi

	if [ "${#label}" -gt "$label_width" ]; then
		label="${label:0:$((label_width - 1))}…"
	fi
	# A leading hyphen would make tmux show the item as disabled.
	case $label in -*) label=" $label" ;; esac
	format_escape label "$label"

	argv_escape key "$key"
	argv_escape label "$label"
	keys+=("$key")
	labels+=("$label")
	format_escape item_command "$item_command"
	commands+=("$item_command")
	is_user+=("$user")
done <<EOF
$(tmux list-keys -T "$table" -F "#{key_string}$WK_SEP#{key_note}$WK_SEP#{key_command}")
EOF

# Your bindings first, then a separator (-1) and tmux's defaults.
order=()
for want in 1 0; do
	[ "$want" = 0 ] && [ "${#order[@]}" -gt 0 ] && order+=(-1)
	i=0
	while [ "$i" -lt "${#keys[@]}" ]; do
		[ "${is_user[$i]}" = "$want" ] && order+=("$i")
		i=$((i + 1))
	done
done
if [ "${#order[@]}" -gt 0 ] && [ "${order[${#order[@]} - 1]}" = -1 ]; then
	unset "order[${#order[@]} - 1]"
fi

total=${#order[@]}
if [ "$total" -eq 0 ]; then
	tmux display-message -c "$client" "whichkey: no bindings in table '$table'"
	exit 0
fi

# Menus taller than the client are silently not drawn, so paginate.
# Reserve rows for the border, the status line and the page navigation.
max_rows=$((${height:-24} - 4))
if [ "$total" -le "$max_rows" ]; then
	per_page=$total
else
	per_page=$((max_rows - 3))
	[ "$per_page" -ge 1 ] || per_page=1
fi
pages=$(((total + per_page - 1) / per_page))
[ "$page" -le "$pages" ] || page=$pages
start=$(((page - 1) * per_page))
end=$((start + per_page))
[ "$end" -le "$total" ] || end=$total

args=()
i=$start
while [ "$i" -lt "$end" ]; do
	n=${order[$i]}
	if [ "$n" = -1 ]; then
		# No separator at the edge of a page.
		[ "$i" -eq "$start" ] || [ "$i" -eq $((end - 1)) ] || args+=("")
	else
		args+=("${labels[$n]}" "${keys[$n]}" "${commands[$n]}")
	fi
	i=$((i + 1))
done

format_escape title "$table"
if [ "$pages" -gt 1 ]; then
	title="$title ($page/$pages)"
	args+=("")
	if [ "$page" -lt "$pages" ]; then
		menu_command nav "$table" $((page + 1))
		format_escape nav "$nav"
		args+=("Next page" C-n "$nav")
	fi
	if [ "$page" -gt 1 ]; then
		menu_command nav "$table" $((page - 1))
		format_escape nav "$nav"
		args+=("Previous page" C-p "$nav")
	fi
fi

tmux display-menu -c "$client" -t "$pane" -T "#[align=centre] $title " -x "$pos_x" -y "$pos_y" "${args[@]}"
exit 0
