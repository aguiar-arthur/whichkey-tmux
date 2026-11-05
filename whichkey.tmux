#!/usr/bin/env bash
# Entry point: run by TPM, or by `run-shell /path/to/whichkey.tmux`.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$CURRENT_DIR/scripts/lib"
# shellcheck source=scripts/lib/quote.sh
source "$LIB/quote.sh"
# shellcheck source=scripts/lib/options.sh
source "$LIB/options.sh"
# shellcheck source=scripts/lib/tmux.sh
source "$LIB/tmux.sh"
# shellcheck source=scripts/lib/bindings.sh
source "$LIB/bindings.sh"
# shellcheck source=scripts/lib/automode.sh
source "$LIB/automode.sh"
# shellcheck source=scripts/lib/debug.sh
source "$LIB/debug.sh"

# Tables where a prefix key has to be bound by hand once its option is None:
# root, plus the copy-mode tables, which replace root in copy mode.
PREFIX_TABLES="root copy-mode copy-mode-vi"

# The options auto mode takes over.
PREFIX_OPTIONS="prefix prefix2"

# bind_menu_keys: @whichkey-key in the prefix table (and @whichkey-root-key,
# if set, in the root table) opens the catalog menu.
bind_menu_keys() {
	local menu open key root_key
	sh_quote menu "$CURRENT_DIR/scripts/menu.sh"
	format_escape menu "$menu"
	tmux_quote open "$menu '#{client_name}' '#{pane_id}' prefix"
	open="run-shell -b $open"
	key=$(get_option @whichkey-key "$WK_DEFAULT_KEY")
	root_key=$(get_option @whichkey-root-key "")

	tmux bind-key -N "Show key bindings" "$key" "$open"
	if [ -n "$root_key" ]; then
		tmux bind-key -n -N "Show key bindings" "$root_key" "$open"
	fi
}

# user_prefix <var> <option>: the key the user configured for <option>
# (prefix or prefix2), saved as @whichkey-<option>. While auto mode is on the
# option is None, so on a config reload fall back to the saved key. If the
# config now sets a different key, give the old one back first.
user_prefix() {
	local _key _saved
	_key=$(tmux show-option -gv "$2")
	_saved=$(get_option "@whichkey-$2" "")
	if [ "$_key" = None ]; then
		_key=$_saved
	else
		if [ -n "$_saved" ] && [ "$_saved" != "$_key" ]; then
			release_key "$_saved" "$2"
		fi
		tmux set-option -g "@whichkey-$2" "$_key"
	fi
	printf -v "$1" '%s' "$_key"
}

# prefix_trigger <var> <delay-ms>: what a prefix key runs in auto mode:
# switch to the prefix table, bump the sequence numbers, note the state and
# check back after the delay (see scripts/auto.sh).
prefix_trigger() {
	local _seconds _run
	ms_to_seconds _seconds "$2"
	auto_command _run '#{client_name}' '#{pane_id}' '#{@whichkey-seq}'
	tmux_quote _run "$_run"
	printf -v "$1" '%s' "switch-client -T prefix ;" \
		" set-option -gF @whichkey-seq '#{e|+:#{@whichkey-seq},1}' ;" \
		" set-option -gF '@whichkey-seq-#{client_name}' '#{@whichkey-seq}' ;" \
		" run-shell -b -d $_seconds $_run"
}

# claim_key <key> <option> <trigger>: bind <key> to the trigger where tmux
# would have handled it as <option>.
claim_key() {
	local table command send_prefix
	for table in $PREFIX_TABLES; do
		tmux bind-key -T "$table" "$1" "$3"
	done
	binding_command command prefix "$1"
	send_prefix_command send_prefix "$2"
	if [ "$command" = "$send_prefix" ]; then
		bind_prefix_standin "$1"
	fi
}

# release_key <key> <option>: undo claim_key.
release_key() {
	local table command send_prefix
	for table in $PREFIX_TABLES; do
		binding_command command "$table" "$1"
		case $command in
		*auto.sh*) tmux unbind-key -T "$table" "$1" ;;
		esac
	done
	binding_command command prefix "$1"
	if is_prefix_standin "$1" "$command"; then
		send_prefix_command send_prefix "$2"
		# shellcheck disable=SC2086 # "send-prefix -2" is two arguments
		tmux bind-key -N "Send the prefix key" -T prefix "$1" $send_prefix
	fi
}

# tmux switches to the prefix table internally, before any key binding, so
# there is no event to hang a timer on. Instead, turn the prefix options off
# and bind their keys ourselves.
setup_auto() {
	local trigger option key
	prefix_trigger trigger "$(get_option @whichkey-delay "$WK_DEFAULT_DELAY")"
	for option in $PREFIX_OPTIONS; do
		user_prefix key "$option"
		[ -n "$key" ] || continue
		tmux set-option -g "$option" None
		claim_key "$key" "$option" "$trigger"
	done
	tmux set-hook -g "$WK_DETACH_HOOK" "set-option -gqu '@whichkey-seq-#{hook_client}'"
}

# Undo setup_auto after the option is turned off and the config reloaded.
teardown_auto() {
	local option key
	for option in $PREFIX_OPTIONS; do
		key=$(get_option "@whichkey-$option" "")
		[ -n "$key" ] && [ "$(tmux show-option -gv "$option")" = None ] || continue
		tmux set-option -g "$option" "$key"
		release_key "$key" "$option"
	done
	tmux set-hook -gu "$WK_DETACH_HOOK" 2>/dev/null
}

# apply_debug_option: start or stop the debug log, starting it afresh once it
# passes 10 MB.
apply_debug_option() {
	case $(get_option @whichkey-debug "$WK_DEFAULT_DEBUG") in
	on | yes | 1)
		mkdir -p "$WK_DEBUG_DIR"
		if [ "$(wc -c <"$WK_DEBUG_LOG" 2>/dev/null || echo 0)" -gt 10485760 ]; then
			: >"$WK_DEBUG_LOG"
		fi
		: >"$WK_DEBUG_FLAG"
		;;
	*) rm -f "$WK_DEBUG_FLAG" ;;
	esac
	# shellcheck disable=SC2119 # no arguments to log
	debug_init
}

main() {
	apply_debug_option
	WK_TMUX_VERSION=$(tmux display-message -p '#{version}')
	if ! version_at_least "$WK_TMUX_VERSION" 3 4; then
		tmux display-message "whichkey-tmux: requires tmux 3.4 or newer"
		return
	fi
	bind_menu_keys
	case $(get_option @whichkey-auto "$WK_DEFAULT_AUTO") in
	on | yes | 1) setup_auto ;;
	*) teardown_auto ;;
	esac
	warm_defaults_cache
}

# warm_defaults_cache: read tmux's built-in bindings now, in the background,
# so the first popup or menu after installing (or upgrading tmux) does not
# wait for it.
warm_defaults_cache() {
	(
		local table defaults
		for table in prefix root copy-mode copy-mode-vi; do
			load_defaults defaults "$table"
		done
	) >/dev/null 2>&1 &
}

main
