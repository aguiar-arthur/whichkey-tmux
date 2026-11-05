#!/usr/bin/env bash
# End-to-end test: runs a private tmux server with real attached clients (on
# pseudo-terminals, via tests/pty_run.py), drives the menu and the auto popup
# with keypresses and checks that the chosen bindings actually fire.
#
# Keys are pressed two ways: `key` sends tmux key names straight to the
# client's key table (send-keys -K), and `typed` writes raw bytes to the
# client's terminal, which tmux parses like real typing. Popups only receive
# cursor and function keys the second way.
#
# Waits are polls on observable state (text drawn on the client, option
# values), not fixed sleeps, so a slow moment does not fail a check.
#
# Usage: tests/e2e.sh
#
# With E2E_WORK=<dir>, the test works in <dir> and keeps it: the client
# logs, and with @whichkey-debug on from the start, the plugin's trace in
# <dir>/cache/whichkey-tmux/debug.log. CI uploads it when the test fails.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/keys.sh
source "$ROOT/scripts/lib/keys.sh"
SOCKET="whichkey-test-$$"
if [ -n "$E2E_WORK" ]; then
	WORK=$E2E_WORK
	mkdir -p "$WORK"
	keep_work=1
else
	WORK=$(mktemp -d "${TMPDIR:-/tmp}/whichkey-test.XXXXXX")
	keep_work=
fi
# Keep the defaults cache and the debug log out of ~/.cache.
export XDG_CACHE_HOME="$WORK/cache"
LOG="$WORK/main.log"
failures=0
pids=()

t() { tmux -L "$SOCKET" "$@"; }

stop() {
	local pid
	t kill-server 2>/dev/null
	# Keep each server's debug trace (see E2E_WORK) in a file of its own.
	if [ -f "$XDG_CACHE_HOME/whichkey-tmux/debug.log" ]; then
		servers=$((${servers:-0} + 1))
		mv "$XDG_CACHE_HOME/whichkey-tmux/debug.log" "$WORK/debug-$servers.log"
	fi
	exec 3>&- 4>&-
	for pid in "${pids[@]}"; do
		kill "$pid" 2>/dev/null
		wait "$pid" 2>/dev/null
	done
	pids=()
}
cleanup() {
	stop
	rm -f "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/$SOCKET"
	[ -n "$keep_work" ] || rm -rf "$WORK"
}
trap cleanup EXIT

# Quoted heredoc: these lines reach tmux exactly as written.
cat >"$WORK/tmux.conf" <<'EOF'
# Stray keys must never reach a shell (C-d would end the session).
set -g remain-on-exit on
set -g default-command 'stty raw -echo; exec cat >/dev/null'
set -g @whichkey-y 1
set -g repeat-time 2000

bind q set -g @wk-test q
bind j set -g @wk-test j
bind G set -g @wk-test G
bind Enter set -g @wk-test Enter
bind '#' set -g @wk-test hash
bind '$' set -g @wk-test dollar
bind '%' set -g @wk-test percent
bind "'" set -g @wk-test squote
bind '"' set -g @wk-test dquote
bind \; set -g @wk-test semicolon
bind '{' set -g @wk-test lbrace
bind '}' set -g @wk-test rbrace
bind '~' set -g @wk-test tilde
bind '\' set -g @wk-test backslash
bind -N "Enter group" g switch-client -T wkgroup
bind -T wkgroup a set -g @wk-test group-a
bind Up set -g @wk-test Up
bind C-Up set -g @wk-test C-Up
bind Home set -g @wk-test Home
bind End set -g @wk-test End
bind PPage set -g @wk-test PPage
bind F5 set -g @wk-test F5
bind M-a set -g @wk-test M-a
bind C-M-a set -g @wk-test C-M-a
bind C-o set -g @wk-test C-o
bind C-n set -g @wk-test C-n
bind -r H resize-pane -L 1
EOF
[ -z "$keep_work" ] || echo "set -g @whichkey-debug on" >>"$WORK/tmux.conf"
cp "$WORK/tmux.conf" "$WORK/auto.conf"
echo "run-shell '$ROOT/whichkey.tmux'" >>"$WORK/tmux.conf"
cat >>"$WORK/auto.conf" <<EOF
set -g prefix2 C-a
bind C-a send-prefix -2
set -g @whichkey-auto on
set -g @whichkey-delay 100
run-shell '$ROOT/whichkey.tmux'
EOF

# wait_for <command...>: poll until it succeeds, for up to 3 seconds.
wait_for() {
	local i=0
	while [ "$i" -lt 60 ]; do
		"$@" && return 0
		sleep 0.05
		i=$((i + 1))
	done
	return 1
}

# attach <fd> <rows> <name>: attach a client of that height, whose terminal
# is typed into through file descriptor <fd> (3 or 4) and drawn into
# $WORK/<name>.log. Sets $client to its name.
attach() {
	local fifo="$WORK/$3.in"
	rm -f "$fifo" "$WORK/$3.log"
	mkfifo "$fifo"
	clients_before=" $(t list-clients -F '#{client_name}' | tr '\n' ' ') "
	TERM=xterm-256color python3 "$ROOT/tests/pty_run.py" "$2" 160 "$WORK/$3.log" \
		tmux -L "$SOCKET" attach -t test <"$fifo" >/dev/null 2>&1 &
	pids+=($!)
	eval "exec $1>\"\$fifo\""
	wait_for new_client
}
new_client() {
	local c
	for c in $(t list-clients -F '#{client_name}'); do
		case $clients_before in *" $c "*) ;; *)
			client=$c
			return 0
			;;
		esac
	done
	return 1
}

# start <rows> [config]: start the server and attach the main client.
start() {
	if [ -n "$keep_work" ]; then
		# With E2E_WORK, also keep tmux's own log (-vv), in $WORK.
		(cd "$WORK" && t -vv -f "$WORK/${2:-tmux.conf}" new-session -d -s test)
	else
		t -f "$WORK/${2:-tmux.conf}" new-session -d -s test
	fi
	attach 3 "$1" main || {
		echo "FAIL: could not attach a client"
		exit 1
	}
	main=$client
}

# Client output since the last mark contains <text>.
mark() { log_mark=$(wc -c <"$LOG"); }
drawn() { tail -c +$((log_mark + 1)) "$LOG" | LC_ALL=C grep -aqF -- "$1"; }

# key <key...>: press keys on the client by name, no waiting.
key() {
	local k code
	for k in "$@"; do
		if key_hex code "$k"; then
			t send-keys -c "$client" -K -H "$code"
		else
			t send-keys -c "$client" -K "$k"
		fi
	done
}

# typed <bytes>: type raw bytes (printf %b escapes) into the main client.
# Menus are driven this way: before tmux 3.8 a menu does not match keys
# from send-keys -K to its items.
typed() { printf '%b' "$1" >&3; }

# open <text> <key...>: press the keys and wait until <text> is drawn.
open() {
	local text=$1
	shift
	mark
	key "$@"
	wait_for drawn "$text"
}

pass() { echo "ok   $1"; }
fail() {
	echo "FAIL $1"
	failures=$((failures + 1))
}
check() {
	if [ "$2" = "$3" ]; then pass "$1"; else fail "$1: expected '$2', got '$3'"; fi
}
fired_is() { [ "$(t show -gqv @wk-test)" = "$1" ]; }
expect_fired() {
	if [ -n "$2" ]; then
		wait_for fired_is "$2"
	else
		sleep 0.4
	fi
	check "$1" "$2" "$(t show -gqv @wk-test)"
	t set -gu @wk-test
}
expect_drawn() {
	if wait_for drawn "$2"; then pass "$1"; else fail "$1: '$2' never drawn"; fi
}
windows_above() { [ "$(t display -p '#{session_windows}')" -gt "$1" ]; }
table_is() { [ "$(t display -p -c "${2:-$client}" '#{client_key_table}')" = "$1" ]; }
# binding <table> <key>: the command bound to <key>, from list-keys' plain
# output (-F is 3.7+, and list-keys <key> lists nothing before 3.8).
binding() {
	t list-keys -T "$1" | awk -v key="$2" '{
		i = 2
		while ($i ~ /^-/) i += ($i == "-T") ? 2 : 1
		if ($i != key) next
		out = $(i + 1)
		for (j = i + 2; j <= NF; j++) out = out " " $j
		print out
	}'
}
option_unset() { [ -z "$(t show -gqv "$1")" ]; }

echo "-- catalog menu"
start 100

# <bytes typed> <@wk-test value>
for pair in "q q" "j j" "G G" "\r Enter" "# hash" "\$ dollar" "% percent" \
	"' squote" "\" dquote" "; semicolon" "{ lbrace" "} rbrace" "~ tilde" \
	"\\\\ backslash" "\016 C-n"; do
	open " prefix " C-b Space || fail "menu did not open for ${pair#* }"
	typed "${pair%% *}"
	expect_fired "menu: ${pair#* }" "${pair#* }"
done

open " prefix " C-b Space
mark
typed g
expect_drawn "menu: a group opens its submenu" " wkgroup "
typed a
expect_fired "group submenu runs its binding" group-a

before=$(t display -p '#{session_windows}')
open " prefix " C-b Space
typed c
wait_for windows_above "$before"
check "built-in binding (new-window)" $((before + 1)) "$(t display -p '#{session_windows}')"

t set -g @whichkey-exclude '('
mark
key C-b Space
expect_drawn "an invalid @whichkey-exclude is reported" "not a valid regex"
wait_for drawn " prefix "
key Escape
t set -gu @whichkey-exclude

stop
start 24
# Short client: several pages, with your bindings on the first one.
open "prefix (1/" C-b Space
if drawn "Enter group" && ! drawn "Choose a window"; then
	pass "page 1 lists your bindings before tmux defaults"
else
	fail "page 1 does not start with your bindings"
fi
# C-n is bound in the config, so the next page moves to NPage.
mark
typed '\033[6~'
expect_drawn "pagination avoids a key you bound" "prefix (2/"
key Escape

echo "-- auto popup"
stop
start 50 auto.conf
check "prefix option is off" None "$(t show -gv prefix)"
check "prefix2 option is off" None "$(t show -gv prefix2)"
check "send-prefix stand-in" "send-keys C-b" "$(binding prefix C-b)"
check "send-prefix -2 stand-in" "send-keys C-a" "$(binding prefix C-a)"

mark
key C-b
check "client_prefix still works" 1 "$(t display -p -c "$client" '#{client_prefix}')"
expect_drawn "popup shows config bindings" "Enter group"
if drawn "Choose a window"; then fail "popup lists a tmux default binding"; else pass "popup hides tmux defaults"; fi
if drawn "send-keys C-"; then fail "popup lists a send-prefix stand-in"; else pass "popup hides the send-prefix stand-ins"; fi
key q
expect_fired "popup: listed key" q

open "Enter group" C-a
key q
expect_fired "prefix2 gets the popup too" q

before=$(t display -p '#{session_windows}')
open "Enter group" C-b
key c
wait_for windows_above "$before"
check "popup: unlisted default key passes through" $((before + 1)) "$(t display -p '#{session_windows}')"

open "Enter group" C-b
mark
key g
expect_drawn "popup follows a group key" " wkgroup "
key a
expect_fired "group popup runs its binding" group-a

mark
key C-b g
expect_drawn "group typed before the delay gets a popup" " wkgroup "
key a
expect_fired "group popup (fast) runs its binding" group-a

# Real typing: tmux parses the bytes into a key, re-encodes it for the
# popup, and popup.sh has to decode it back.
for pair in 'Up \033[A' 'C-Up \033[1;5A' 'Home \033[H' 'End \033[F' 'PPage \033[5~' \
	'F5 \033[15~' 'M-a \033a' 'C-M-a \033\001' 'C-o \017' 'Enter \r' 'q q' \
	'percent %' 'semicolon ;' 'dquote "'; do
	open "Enter group" C-b || fail "popup did not open for ${pair%% *}"
	typed "${pair#* }"
	expect_fired "typed into the popup: ${pair%% *}" "${pair%% *}"
done

open "Enter group" C-b
typed '\033'
wait_for table_is root
check "typed Escape closes the popup and leaves the prefix table" root \
	"$(t display -p -c "$client" '#{client_key_table}')"

# Fast typing: the key lands before the delay, so no popup may appear. If one
# did, it would swallow the next key.
key C-b q
expect_fired "fast path runs the binding" q
key j
expect_fired "fast path leaves no popup behind" ""

# A repeat (-r) binding keeps the client in the prefix table, but it changed
# the layout, so the popup must stay away.
t split-window -h -t test
mark
key C-b H
sleep 0.5
if drawn "Enter group"; then fail "popup appeared during a repeat binding"; else pass "no popup during a repeat binding"; fi
t switch-client -c "$client" -T root

t copy-mode -t test
key C-b q
expect_fired "prefix works in copy mode" q
t send-keys -X -t test cancel

echo "-- several clients"
attach 4 50 second
second=$client
client=$main
mark
t send-keys -c "$main" -K C-b
t send-keys -c "$second" -K C-b
expect_drawn "a prefix on another client does not cancel the popup" "Enter group"
key Escape
t send-keys -c "$second" -K Escape
wait_for table_is root "$second"
if option_unset "@whichkey-seq-$second"; then
	fail "no sequence number for the second client"
else
	pass "each client has its own sequence number"
fi
t detach-client -t "$second"
exec 4>&-
if wait_for option_unset "@whichkey-seq-$second"; then
	pass "detaching removes the client's sequence number"
else
	fail "sequence number left behind after detach"
fi

echo "-- options"
t set -g @whichkey-debug on
t run-shell "$ROOT/whichkey.tmux"
open "Enter group" C-b
key Escape
debug_log="$XDG_CACHE_HOME/whichkey-tmux/debug.log"
logged() { grep -q "== .* $1" "$debug_log" 2>/dev/null; }
if wait_for logged auto.sh && wait_for logged popup.sh; then
	pass "@whichkey-debug traces the scripts"
else
	fail "@whichkey-debug: auto.sh or popup.sh missing from $debug_log"
fi
t set -g @whichkey-debug off
t run-shell "$ROOT/whichkey.tmux"
if [ -e "$XDG_CACHE_HOME/whichkey-tmux/debug.on" ]; then
	fail "@whichkey-debug off does not stop tracing"
else
	pass "@whichkey-debug off stops tracing"
fi

t set -g @whichkey-auto off
t run-shell "$ROOT/whichkey.tmux"
check "turning auto off restores the prefix" C-b "$(t show -gv prefix)"
check "turning auto off restores prefix2" C-a "$(t show -gv prefix2)"
check "turning auto off restores send-prefix" send-prefix "$(binding prefix C-b)"
check "turning auto off restores send-prefix -2" "send-prefix -2" "$(binding prefix C-a)"
check "turning auto off unbinds the trigger" "" "$(binding root C-b)"

t set -g @whichkey-auto on
t run-shell "$ROOT/whichkey.tmux"
t set -g prefix C-x
t run-shell "$ROOT/whichkey.tmux"
check "a new prefix is taken over" None "$(t show -gv prefix)"
check "the old prefix key is released" "" "$(binding root C-b)"
check "the old prefix gets send-prefix back" send-prefix "$(binding prefix C-b)"
open "Enter group" C-x
expect_drawn "the new prefix shows the popup" "Enter group"
key Escape

stop
start 10 auto.conf
open " prefix " C-b
expect_drawn "popup too small for every binding says how many more" "more"
key Escape

[ "$failures" -eq 0 ] && echo "all passed" || echo "$failures failed"
exit "$failures"
