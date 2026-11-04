#!/usr/bin/env bash
# Run after @whichkey-delay, once by the prefix key and again after a group
# key chosen in the popup. If the client is still waiting in a key table and
# nothing happened since, pop up the bindings your config defines there,
# laid out in columns.
#
# Usage: auto.sh <client> <pane> <seq> <state>
#
# <seq> is @whichkey-seq when the prefix was pressed; a newer prefix press
# cancels this run. <state> is WK_STATE_FORMAT expanded at the same moment.
# tmux has no "a key was pressed" signal, and after a repeat (-r) binding the
# client stays in the prefix table, so a changed state is how we tell that a
# key did something (resized, moved to another pane or window...).

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
source "$CURRENT_DIR/helpers.sh"

client=$1
pane=$2
seq=$3
state=$4

# still_waiting <var>: sets <var> to the client's key table and succeeds if
# the popup should still be shown.
still_waiting() {
	local _table _seq _state
	IFS=$WK_SEP read -r _table _seq _state <<EOF
$(tmux display-message -p -c "$client" "#{client_key_table}$WK_SEP#{@whichkey-seq}$WK_SEP$WK_STATE_FORMAT")
EOF
	printf -v "$1" '%s' "$_table"
	[ "$_table" != root ] && [ "$_seq" = "$seq" ] && [ "$_state" = "$state" ]
}

still_waiting table || exit 0

IFS=$WK_SEP read -r width height version prefix label_width delay <<EOF
$(tmux display-message -p -c "$client" "#{client_width}$WK_SEP#{client_height}$WK_SEP#{version}$WK_SEP#{@whichkey-prefix}$WK_SEP#{@whichkey-label-width}$WK_SEP#{@whichkey-delay}")
EOF
label_width=${label_width:-40}

load_defaults defaults "$version" "$table"

keys=()
labels=()
groups=()
group_keys=" "
key_width=0
text_width=0
while IFS= read -r line; do
	[ -n "$line" ] || continue
	case $defaults in *"
$line
"*) continue ;; esac
	IFS=$WK_SEP read -r key note command <<<"$line"
	# Our stand-in for send-prefix, see whichkey.tmux.
	[ "$key" = "$prefix" ] && [ "$command" = "send-keys $prefix" ] && continue

	if [[ $command =~ ^switch-client\ -T\ ([^ ]+)$ ]]; then
		label="+${note:-${BASH_REMATCH[1]}}"
		groups+=(1)
		group_keys="$group_keys$key "
	else
		label=${note:-$command}
		groups+=(0)
	fi
	if [ "${#label}" -gt "$label_width" ]; then
		label="${label:0:$((label_width - 3))}..."
	fi
	keys+=("$key")
	labels+=("$label")
	[ "${#key}" -le "$key_width" ] || key_width=${#key}
	[ "${#label}" -le "$text_width" ] || text_width=${#label}
done <<EOF
$(tmux list-keys -T "$table" -F "#{key_string}$WK_SEP#{key_note}$WK_SEP#{key_command}")
EOF

total=${#keys[@]}
[ "$total" -gt 0 ] || exit 0

# Cell: "key → label", columns separated by a gap, one space of padding.
gap=4
cell=$((key_width + 3 + text_width))
cols=$(((width - 4 + gap) / (cell + gap)))
[ "$cols" -ge 1 ] || cols=1
rows=$(((total + cols - 1) / cols))
max_rows=$((height - 4))
[ "$max_rows" -ge 1 ] || max_rows=1
if [ "$rows" -gt "$max_rows" ]; then
	# Too many to fit: fill the grid and use the last cell for a count.
	rows=$max_rows
	shown=$((rows * cols - 1))
else
	# Rebalance so the last column is not nearly empty.
	cols=$(((total + rows - 1) / rows))
	shown=$total
fi

key_color=$'\e[1;35m' group_color=$'\e[34m' dim=$'\e[2m' reset=$'\e[0m'
content=$(mktemp "${TMPDIR:-/tmp}/whichkey.XXXXXX")
r=0
while [ "$r" -lt "$rows" ]; do
	line=" "
	c=0
	while [ "$c" -lt "$cols" ]; do
		i=$((c * rows + r))
		[ "$c" -eq 0 ] || [ "$i" -gt "$shown" ] || printf -v line '%s%*s' "$line" "$gap" ''
		if [ "$i" -lt "$shown" ]; then
			color=$reset
			[ "${groups[$i]}" = 1 ] && color=$group_color
			printf -v line '%s%s%*s%s %s→%s %s%-*s%s' "$line" \
				"$key_color" "$key_width" "${keys[$i]}" "$reset" \
				"$dim" "$reset" "$color" "$text_width" "${labels[$i]}" "$reset"
		elif [ "$i" -eq "$shown" ] && [ "$shown" -lt "$total" ]; then
			printf -v line '%s%s… %d more%s' "$line" "$dim" $((total - shown)) "$reset"
		fi
		c=$((c + 1))
	done
	printf '%s\n' "$line" >>"$content"
	r=$((r + 1))
done

popup_width=$((cols * cell + (cols - 1) * gap + 4))
[ "$popup_width" -le "$width" ] || popup_width=$width

# Re-check right before drawing: a key pressed while we were building the
# grid already ran its binding.
if ! still_waiting now || [ "$now" != "$table" ]; then
	rm -f "$content"
	exit 0
fi
tmux display-popup -c "$client" -t "$pane" -E -b rounded -T " $table " \
	-x C -y S -w "$popup_width" -h $((rows + 2)) \
	"$CURRENT_DIR/popup.sh" "$client" "$pane" "$table" "$content" \
	"$seq" "${delay:-200}" "$group_keys" ||
	rm -f "$content"
exit 0
