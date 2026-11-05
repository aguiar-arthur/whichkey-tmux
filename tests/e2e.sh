#!/usr/bin/env bash
# End-to-end test: runs a private tmux server with a real attached client
# (via macOS script(1)), drives the menu and the auto popup with simulated
# keypresses and checks that the chosen bindings actually fire.
#
# Waits are polls on observable state (text drawn on the client, option
# values), not fixed sleeps, so a slow moment does not fail a check.
#
# Usage: tests/e2e.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/keys.sh
source "$ROOT/scripts/lib/keys.sh"
SOCKET="whichkey-test-$$"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/whichkey-test.XXXXXX")
LOG="$WORK/client.log"
failures=0
feeder=

t() { tmux -L "$SOCKET" "$@"; }

stop() {
	t kill-server 2>/dev/null
	if [ -n "$feeder" ]; then
		kill "$feeder" 2>/dev/null
		wait "$feeder" 2>/dev/null
	fi
	feeder=
}
trap 'stop; rm -rf "$WORK" "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/$SOCKET"' EXIT

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
bind PPage set -g @wk-test PPage
bind M-a set -g @wk-test M-a
bind C-o set -g @wk-test C-o
bind -r H resize-pane -L 1
EOF
cp "$WORK/tmux.conf" "$WORK/auto.conf"
echo "run-shell '$ROOT/whichkey.tmux'" >>"$WORK/tmux.conf"
cat >>"$WORK/auto.conf" <<EOF
set -g @whichkey-auto on
set -g @whichkey-delay 100
run-shell '$ROOT/whichkey.tmux'
EOF

# start <rows> [config]: start the server and attach a client of that height.
start() {
	: >"$LOG"
	t -f "$WORK/${2:-tmux.conf}" new-session -d -s test
	(sleep 300 | TERM=xterm-256color script -F -q "$LOG" \
		sh -c "stty rows $1 cols 160; exec tmux -L $SOCKET attach -t test") >/dev/null 2>&1 &
	feeder=$!
	client=
	wait_for attached || {
		echo "FAIL: could not attach a client"
		exit 1
	}
}
attached() {
	client=$(t list-clients -F '#{client_name}' 2>/dev/null | head -1)
	[ -n "$client" ]
}

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

# Client output since the last mark contains <text>.
mark() { log_mark=$(wc -c <"$LOG"); }
drawn() { tail -c +$((log_mark + 1)) "$LOG" | LC_ALL=C grep -aqF -- "$1"; }

# key <key...>: press keys on the client, no waiting.
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

# open <text>: press the given keys and wait until <text> is drawn.
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
table_is() { [ "$(t display -p -c "$client" '#{client_key_table}')" = "$1" ]; }

echo "-- catalog menu"
start 100

for pair in "q q" "j j" "G G" "Enter Enter" "# hash" "\$ dollar" "% percent" \
	"' squote" "\" dquote" "; semicolon" "{ lbrace" "} rbrace" "~ tilde" "\\ backslash"; do
	k=${pair%% *}
	open " prefix " C-b Space || fail "menu did not open for $k"
	key "$k"
	expect_fired "key $k" "${pair#* }"
done

open " prefix " C-b Space
open " wkgroup " g
key a
expect_fired "group submenu" group-a

before=$(t display -p '#{session_windows}')
open " prefix " C-b Space
key c
wait_for windows_above "$before"
check "built-in binding (new-window)" $((before + 1)) "$(t display -p '#{session_windows}')"

stop
start 24
# Short client: several pages, with your bindings on the first one.
open "prefix (1/" C-b Space
if drawn "Enter group" && ! drawn "Choose a window"; then
	pass "page 1 lists your bindings before tmux defaults"
else
	fail "page 1 does not start with your bindings"
fi
mark
key C-n
expect_drawn "pagination" "prefix (2/"
key Escape

echo "-- auto popup"
stop
start 50 auto.conf
check "prefix option is off" None "$(t show -gv prefix)"
check "send-prefix stand-in" "send-keys C-b" "$(t list-keys -T prefix -F '#{key_command}' C-b)"

mark
key C-b
check "client_prefix still works" 1 "$(t display -p -c "$client" '#{client_prefix}')"
expect_drawn "popup shows config bindings" "Enter group"
if drawn "Choose a window"; then fail "popup lists a tmux default binding"; else pass "popup hides tmux defaults"; fi
key q
expect_fired "popup: listed key" q

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

open "Enter group" C-b
key Escape
wait_for table_is root
check "popup: Escape leaves the prefix table" root "$(t display -p -c "$client" '#{client_key_table}')"

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

# send-keys -K does not deliver cursor keys to a popup (real typing does),
# so feed popup.sh raw terminal bytes on a pty of its own instead.
decode() {
	echo x >"$WORK/content"
	(sleep 0.3; printf '%b' "$1"; sleep 0.5) |
		TMUX="$(t display -p '#{socket_path}'),0,0" script -q /dev/null \
			bash "$ROOT/scripts/popup.sh" "$client" "$(t display -p '#{pane_id}')" prefix \
			"$WORK/content" 0 100 " g " >/dev/null 2>&1
}
for pair in 'Up \033[A' 'Up \033OA' 'C-Up \033[1;5A' 'PPage \033[5~' 'M-a \033a' \
	'C-o \017' 'Enter \r' 'q q' 'percent %' 'semicolon ;'; do
	decode "${pair#* }"
	expect_fired "popup decodes ${pair#* }" "${pair%% *}"
done
t switch-client -c "$client" -T prefix
decode '\033'
wait_for table_is root
check "popup: lone Escape closes and leaves prefix" root "$(t display -p -c "$client" '#{client_key_table}')"

stop
start 10 auto.conf
open " prefix " C-b
expect_drawn "popup too small for every binding says how many more" "more"
key Escape

t set -g @whichkey-auto off
t run-shell "$ROOT/whichkey.tmux"
check "turning auto off restores the prefix" C-b "$(t show -gv prefix)"
check "turning auto off restores send-prefix" send-prefix "$(t list-keys -T prefix -F '#{key_command}' C-b)"

[ "$failures" -eq 0 ] && echo "all passed" || echo "$failures failed"
exit "$failures"
