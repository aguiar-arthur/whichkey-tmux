#!/usr/bin/env bash
# Unit tests for scripts/lib: no tmux server needed. Where a function talks
# to tmux, a tmux() shell function stands in for it.
#
# Usage: tests/unit.sh

# shellcheck source-path=SCRIPTDIR/../scripts/lib
# The pair loops split "$pair" into words on purpose (SC2086, SC2089,
# SC2090), and decode bytes with \xNN printf formats (SC2059).
# shellcheck disable=SC2086,SC2089,SC2090,SC2059

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/scripts/lib"
source "$LIB/quote.sh"
source "$LIB/options.sh"
source "$LIB/tmux.sh"
source "$LIB/bindings.sh"
source "$LIB/keys.sh"
source "$LIB/layout.sh"
source "$LIB/automode.sh"
source "$LIB/style.sh"

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
# shellcheck disable=SC2016 # literal $ and backticks on purpose
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

echo "-- style"
for pair in 'fg=magenta,bold|\e[0;35;1m' 'fg=blue|\e[0;34m' 'bg=red dim|\e[0;41;2m' \
	'fg=brightcyan|\e[0;96m' 'fg=colour208|\e[0;38;5;208m' 'fg=color8|\e[0;38;5;8m' \
	'fg=#bd93f9,italics|\e[0;38;2;189;147;249;3m' 'default|\e[0m' '|\e[0m' 'fg=nope,bold|\e[0;1m'; do
	style_sgr out "${pair%%|*}"
	printf -v want '%b' "${pair#*|}"
	check "style_sgr ${pair%%|*}" "$want" "$out"
done

mkdir -p "$WORK/glob" && touch "$WORK/glob/bold" && (cd "$WORK/glob" && style_sgr out 'fg=red *' && printf '%s' "$out" >"$WORK/glob/out")
printf -v want '%b' '\e[0;31m'
check "style_sgr does not glob" "$want" "$(cat "$WORK/glob/out")"

echo "-- tmux queries (fake tmux)"
tmux() { printf 'a%s%sc d\n' "$WK_SEP" "$WK_SEP"; }
read_formats client x '#{x}' y '#{y}' z '#{z}'
check "read_formats keeps empty fields" "a||c d" "$x|$y|$z"
tmux() { printf '%s\n' 'a\037\037c d'; }
read_formats client x '#{x}' y '#{y}' z '#{z}'
check "read_formats: separator escaped by tmux < 3.7" "a||c d" "$x|$y|$z"
tmux() { echo "$*" | grep -q -- ' -c ' && echo with-client || echo no-client; }
read_formats '' x '#{x}'
check "read_formats without a client" "no-client" "$x"

# load_bindings: a cached default, a changed default, a new binding, a group.
WK_TMUX_VERSION=9.9
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
load_bindings prefix
check "load_bindings keys" "c d G g" "${WK_KEYS[*]}"
check "load_bindings user vs default" "0 1 1 1" "${WK_IS_USER[*]}"
check "load_bindings groups" "|||git" "${WK_GROUP[0]}|${WK_GROUP[1]}|${WK_GROUP[2]}|${WK_GROUP[3]}"
binding_label out 2
check "binding_label: note" "Lazygit" "$out"
binding_label out 1
check "binding_label: command without a note" "kill-pane" "$out"
binding_label out 3
check "binding_label: group without a note" "+git" "$out"
WK_NOTES[3]="+Git"
binding_label out 3
check "binding_label: group note that has its own +" "+Git" "$out"
WK_NOTES[3]="Git"
binding_label out 3
check "binding_label: group note" "+Git" "$out"
list_bindings list prefix
lookup_command out "$list" g
check "lookup_command" "switch-client -T git" "$out"
lookup_command out "$list" c
check "lookup_command: first line" "new-window" "$out"
lookup_command out "$list" X
check "lookup_command: unbound key" "" "$out"

# Before tmux 3.8, list-keys' plain output is parsed.
plain='bind-key    -T prefix C-b     send-prefix
bind-key    -T prefix \#      display-message hi
bind-key    -T prefix \;      last-pane
bind-key    -T prefix \\      display-message bs
bind-key -r -T prefix H       resize-pane -L
bind-key    -T prefix -       delete-buffer
bind-key    -T prefix g       switch-client -T grp
bind-key    -T prefix x       display-message "a  b"
bind-key    -T prefix "M-{"   send-keys -X previous-paragraph'
# list-keys -N lists the bindings with a note in list-keys' order.
notes='C-b     Send the prefix key
#       A note
;       Last pane
\       Back slash
H       Resize left'
parse_list_keys out "$plain" "$notes"
want="C-b${WK_SEP}Send the prefix key${WK_SEP}send-prefix
#${WK_SEP}A note${WK_SEP}display-message hi
;${WK_SEP}Last pane${WK_SEP}last-pane
\\${WK_SEP}Back slash${WK_SEP}display-message bs
H${WK_SEP}Resize left${WK_SEP}resize-pane -L
-${WK_SEP}${WK_SEP}delete-buffer
g${WK_SEP}${WK_SEP}switch-client -T grp
x${WK_SEP}${WK_SEP}display-message \"a  b\"
M-{${WK_SEP}${WK_SEP}send-keys -X previous-paragraph"
check "parse_list_keys" "$want" "$out"

WK_TMUX_VERSION=3.4
tmux() {
	case " $* " in
	*" -F "*) echo "command list-keys: unknown flag -F" >&2 ;;
	*" -N "*) printf '%s\n' "$notes" ;;
	*) printf '%s\n' "$plain" ;;
	esac
}
list_bindings out prefix
check "list_bindings before 3.7 reads the plain output" "$want" "$out"
lookup_command out "$out" H
check "lookup_command before 3.7" "resize-pane -L" "$out"

# tmux 3.7: every table is listed with -F and filtered.
WK_TMUX_VERSION=3.7c
tmux() {
	case " $* " in
	*" -T "*) ;; # 3.7 prints nothing for a table with one binding
	*)
		printf 'root%sC-b%s%sswitch-client -T prefix\n' "$WK_SEP" "$WK_SEP" "$WK_SEP"
		printf 'grp%sa%sA note%sdisplay-message a\n' "$WK_SEP" "$WK_SEP" "$WK_SEP"
		printf 'grp2%sb%s%sdisplay-message b\n' "$WK_SEP" "$WK_SEP" "$WK_SEP"
		;;
	esac
}
list_bindings out grp
check "list_bindings on 3.7 filters every table" "a${WK_SEP}A note${WK_SEP}display-message a" "$out"

for v in '3.4 yes' '3.7c yes' '3.10 yes' '4.0 yes' '3.3a no' '2.9 no' 'next-3.9 yes' 'master yes'; do
	set -- $v
	version_at_least "$1" 3 4 && r=yes || r=no
	check "version_at_least $1 3.4" "$2" "$r"
done
unset -f tmux

echo "-- whichkey.tmux (fake tmux)"
# The fake server: answers display-message from F_* variables and list-keys
# from F_LIST_<table>, and records every call in CALLS.
fake_format() {
	case $1 in
	'#{version}') printf 3.8 ;;
	'#{@whichkey-auto}') printf '%s' "$F_AUTO" ;;
	'#{@whichkey-key}') printf '%s' "$F_KEY" ;;
	'#{@whichkey-bound-key}') printf '%s' "$F_BOUND_KEY" ;;
	'#{prefix}') printf '%s' "$F_PREFIX" ;;
	'#{prefix2}') printf None ;;
	'#{@whichkey-prefix}') printf '%s' "$F_SAVED_PREFIX" ;;
	esac
}
tmux() {
	local fmt piece out='' first=1 pieces list
	CALLS+=("$*")
	case $1 in
	display-message)
		fmt=${!#}
		IFS=$WK_SEP read -r -a pieces <<<"$fmt"
		for piece in "${pieces[@]}"; do
			[ "$first" = 1 ] || out="$out$WK_SEP"
			first=0
			out="$out$(fake_format "$piece")"
		done
		printf '%s\n' "$out"
		;;
	list-keys)
		list="F_LIST_${3//-/_}"
		printf '%s\n' "${!list}"
		;;
	esac
}
# whichkey_load: run whichkey.tmux's main against the fake server.
whichkey_load() {
	CALLS=()
	unset TABLE_prefix TABLE_root TABLE_copy_mode TABLE_copy_mode_vi
	main
}
# call_with <text>: the recorded call containing <text>.
call_with() {
	local c
	for c in "${CALLS[@]}"; do
		case $c in *"$1"*) printf '%s' "$c" && return ;; esac
	done
}
# before <a> <b> <text>: in <text>, <a> comes before <b>.
before() {
	case $3 in *"$1"*"$2"*) echo yes ;; *) echo no ;; esac
}

source "$ROOT/whichkey.tmux"
warm_defaults_cache() { :; }
F_LIST_prefix="C-b${WK_SEP}Send the prefix key${WK_SEP}send-prefix
Space${WK_SEP}Show key bindings${WK_SEP}run-shell -b \"'$ROOT/scripts/menu.sh' '#{client_name}' '#{pane_id}' prefix\""
F_LIST_root='' F_LIST_copy_mode='' F_LIST_copy_mode_vi=''

F_AUTO=on F_KEY='' F_BOUND_KEY='' F_PREFIX=C-b F_SAVED_PREFIX=''
whichkey_load
check "load: at most 4 tmux calls" yes "$([ "${#CALLS[@]}" -le 4 ] && echo yes || echo "no (${#CALLS[@]})")"
setup=$(call_with "prefix None")
check "setup: prefix None only after the triggers are bound" yes \
	"$(before "bind-key -T copy-mode-vi C-b" "set-option -g prefix None" "$setup")"
check "setup: send-prefix replaced before prefix None" yes \
	"$(before "send-keys C-b" "set-option -g prefix None" "$setup")"

F_KEY=F1 F_BOUND_KEY=Space
whichkey_load
check "a changed @whichkey-key unbinds the old key" yes \
	"$(before "unbind-key -T prefix Space" "bind-key -N Show key bindings F1" "$(call_with "F1")")"

F_AUTO=off F_KEY='' F_BOUND_KEY='' F_PREFIX=None F_SAVED_PREFIX=C-b
F_LIST_root="C-b${WK_SEP}${WK_SEP}switch-client -T prefix ; run-shell -b '/x/auto.sh'"
F_LIST_prefix="C-b${WK_SEP}Send the prefix key${WK_SEP}send-keys C-b"
whichkey_load
teardown=$(call_with "set-option -g prefix C-b")
check "teardown: prefix restored before anything else" yes \
	"$(before "set-option -g prefix C-b" "unbind-key -T root C-b" "$teardown")"
check "teardown: send-prefix restored" yes \
	"$(before "unbind-key -T root C-b" "send-prefix" "$teardown")"
unset -f tmux

echo
[ "$failures" -eq 0 ] && echo "all passed" || echo "$failures failed"
exit "$failures"
