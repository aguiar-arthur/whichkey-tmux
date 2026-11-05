#!/usr/bin/env bash
# Unit tests for scripts/lib: no tmux server needed. Where a function talks
# to tmux, a tmux() shell function stands in for it.
#
# Usage: tests/unit.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/scripts/lib"
source "$LIB/quote.sh"
source "$LIB/options.sh"
source "$LIB/tmux.sh"
source "$LIB/bindings.sh"
source "$LIB/keys.sh"
source "$LIB/layout.sh"
source "$LIB/automode.sh"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/whichkey-unit.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
failures=0

check() {
	if [ "$2" = "$3" ]; then
		echo "ok   $1"
	else
		echo "FAIL $1: expected '$2', got '$3'"
		failures=$((failures + 1))
	fi
}

echo "-- quote"
format_escape out 'a#{b}##'
check "format_escape doubles #" 'a##{b}####' "$out"
tmux_quote out 'plain text'
check "tmux_quote without '" "'plain text'" "$out"
tmux_quote out "it's \$HOME \"x\" \\"
check "tmux_quote with '" "\"it's \\\$HOME \\\"x\\\" \\\\\"" "$out"
argv_escape out 'M-;'
check "argv_escape trailing ;" 'M-\;' "$out"
argv_escape out 'a;b'
check "argv_escape inner ; untouched" 'a;b' "$out"
for s in "plain" "it's" "a b  c" '$(x) `y` \z'; do
	sh_quote out "$s"
	eval "set -- $out"
	check "sh_quote round-trips: $s" "$s" "$1"
done
truncate_label out "abcdefgh" 5 "..."
check "truncate_label cuts" "ab..." "$out"
truncate_label out "abcde" 5 "..."
check "truncate_label keeps what fits" "abcde" "$out"

echo "-- keys"
# What tmux sends a popup for each key (measured by typing into a real
# client): Home and End arrive as [1~ and [4~, not [H and [F.
for pair in 'Up 1b [A' 'Up 1b OA' 'Down 1b [B' 'Home 1b [1~' 'End 1b [4~' 'Home 1b OH' \
	'End 1b [F' 'C-Up 1b [1;5A' 'M-S-Left 1b [1;4D' 'C-M-S-Right 1b [1;8C' 'C-Home 1b [1;5H' \
	'PPage 1b [5~' 'NPage 1b [6~' 'IC 1b [2~' 'DC 1b [3~' 'C-DC 1b [3;5~' 'BTab 1b [Z' \
	'F1 1b OP' 'F4 1b OS' 'C-F1 1b [1;5P' 'F5 1b [15~' 'S-F5 1b [15;2~' 'F12 1b [24~' \
	'M-a 1b a' 'M-A 1b A' 'M-; 1b ;' 'M-O 1b O' 'M-[ 1b [' \
	'Enter 0d' 'Tab 09' 'BSpace 7f' 'Space 20' 'C-Space 00' 'C-a 01' 'C-o 0f' 'C-z 1a' \
	'C-\ 1c' 'C-_ 1f' 'q 71' '% 25' '; 3b' '" 22' "' 27" '\ 5c' '~ 7e'; do
	set -- $pair
	decode_key out "$2" "$3"
	check "decode_key $2 $3" "$1" "$out"
done
for pair in 'C-M-a 01' 'M-Enter 0d' 'M-BSpace 7f' 'M-Space 20'; do
	set -- $pair
	printf -v byte "\\x$2"
	decode_key out 1b "$byte"
	check "decode_key Escape $2" "$1" "$out"
done
decode_key out c3 $'\xa9'
check "decode_key UTF-8" "é" "$out"
for rest in "" "[99~" "[2;9A" "[5A" "[1;5" "OX"; do
	decode_key out 1b "$rest"
	check "decode_key no key for Escape '$rest'" "" "$out"
done
needs_rest 1b && needs_rest c3 && ! needs_rest 61 && ! needs_rest 80 && r=yes || r=no
check "needs_rest" yes "$r"

for pair in '; 3b' 'a 61' '{ 7b' "' 27" '" 22'; do
	set -- $pair
	key_hex out "$1"
	check "key_hex $1" "$2" "$out"
done
key_hex out Up && r=yes || r=no
check "key_hex named key" no "$r"
key_hex out "é" && r=yes || r=no
check "key_hex non-ASCII" no "$r"

echo "-- layout"
paginate 10 20 1
check "paginate: fits on one page" "10 1 1 0 10" "$PER_PAGE $PAGES $PAGE $START $END"
paginate 50 20 2
check "paginate: page 2 of 3" "17 3 2 17 34" "$PER_PAGE $PAGES $PAGE $START $END"
paginate 50 20 9
check "paginate: clamps the page" "3 34 50" "$PAGE $START $END"
paginate 5 2 1
check "paginate: at least one row per page" "1 5" "$PER_PAGE $PAGES"

grid_layout 10 20 4 100 10
check "grid_layout: rebalances columns" "4 3 10" "$COLS $ROWS $SHOWN"
grid_layout 40 20 4 100 5
check "grid_layout: overflow keeps a cell for the count" "4 5 19" "$COLS $ROWS $SHOWN"
grid_layout 3 200 4 100 5
check "grid_layout: at least one column" "1 3 3" "$COLS $ROWS $SHOWN"

echo "-- automode"
ms_to_seconds out 200
check "ms_to_seconds 200" 0.200 "$out"
ms_to_seconds out 1500
check "ms_to_seconds 1500" 1.500 "$out"
auto_command out "/dev/ttys001" "%1" 7
eval "set -- $out"
check "auto_command runs auto.sh" "$ROOT/scripts/auto.sh" "$1"
check "auto_command arguments" "/dev/ttys001 %1 7 $WK_STATE_FORMAT" "$2 $3 $4 $5"
seq_format out /dev/ttys001
check "seq_format" '#{@whichkey-seq-/dev/ttys001}' "$out"
send_prefix_command out prefix2
check "send_prefix_command prefix2" "send-prefix -2" "$out"
is_prefix_standin C-b "send-keys C-b" && r=yes || r=no
check "is_prefix_standin" yes "$r"
is_prefix_standin C-b "send-prefix" && r=yes || r=no
check "is_prefix_standin send-prefix" no "$r"

echo "-- tmux queries (fake tmux)"
tmux() { printf 'a%s%sc d\n' "$WK_SEP" "$WK_SEP"; }
read_formats client x '#{x}' y '#{y}' z '#{z}'
check "read_formats keeps empty fields" "a||c d" "$x|$y|$z"

# load_bindings: a cached default, a changed default, a new binding, a group.
export XDG_CACHE_HOME="$WORK/cache"
mkdir -p "$XDG_CACHE_HOME/whichkey-tmux"
printf 'c%sCreate a new window%snew-window\nd%s%sdetach-client\n' \
	"$WK_SEP" "$WK_SEP" "$WK_SEP" "$WK_SEP" >"$XDG_CACHE_HOME/whichkey-tmux/defaults-9.9-prefix"
tmux() {
	printf 'c%sCreate a new window%snew-window\n' "$WK_SEP" "$WK_SEP"
	printf 'd%s%skill-pane\n' "$WK_SEP" "$WK_SEP"
	printf 'G%sLazygit%sdisplay-popup -E lazygit\n' "$WK_SEP" "$WK_SEP"
	printf 'g%s%sswitch-client -T git\n' "$WK_SEP" "$WK_SEP"
}
load_bindings prefix 9.9
check "load_bindings keys" "c d G g" "${WK_KEYS[*]}"
check "load_bindings user vs default" "0 1 1 1" "${WK_IS_USER[*]}"
check "load_bindings groups" "|||git" "${WK_GROUP[0]}|${WK_GROUP[1]}|${WK_GROUP[2]}|${WK_GROUP[3]}"
binding_label out 2
check "binding_label: note" "Lazygit" "$out"
binding_label out 1
check "binding_label: command without a note" "kill-pane" "$out"
binding_label out 3
check "binding_label: group without a note" "+git" "$out"
unset -f tmux

echo
[ "$failures" -eq 0 ] && echo "all passed" || echo "$failures failed"
exit "$failures"
