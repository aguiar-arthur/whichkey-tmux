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
# shellcheck source=scripts/lib/automode.sh
source "$LIB/automode.sh"

# Tables where the prefix key has to be bound by hand once the prefix option
# is None: root, plus the copy-mode tables, which replace root in copy mode.
PREFIX_TABLES="root copy-mode copy-mode-vi"

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

# user_prefix <var>: the prefix key the user configured. While auto mode is
# on the prefix option is None, so on a config reload fall back to the key
# we saved.
user_prefix() {
	local _prefix
	_prefix=$(tmux show-option -gv prefix)
	if [ "$_prefix" = None ]; then
		_prefix=$(get_option @whichkey-prefix "")
	else
		tmux set-option -g @whichkey-prefix "$_prefix"
	fi
	printf -v "$1" '%s' "$_prefix"
}

# prefix_trigger <var> <delay-ms>: what the prefix key runs in auto mode:
# switch to the prefix table, bump a sequence number, note the state and
# check back after the delay (see scripts/auto.sh).
prefix_trigger() {
	local _seconds _run
	ms_to_seconds _seconds "$2"
	auto_command _run '#{client_name}' '#{pane_id}' '#{@whichkey-seq}'
	tmux_quote _run "$_run"
	printf -v "$1" '%s' "switch-client -T prefix ; set-option -gF @whichkey-seq '#{e|+:#{@whichkey-seq},1}' ; run-shell -b -d $_seconds $_run"
}

# tmux switches to the prefix table internally, before any key binding, so
# there is no event to hang a timer on. Instead, turn the prefix option off
# and bind the key ourselves.
setup_auto() {
	local prefix trigger table command
	user_prefix prefix
	[ -n "$prefix" ] || return

	prefix_trigger trigger "$(get_option @whichkey-delay "$WK_DEFAULT_DELAY")"
	tmux set-option -g prefix None
	for table in $PREFIX_TABLES; do
		tmux bind-key -T "$table" "$prefix" "$trigger"
	done
	binding_command command prefix "$prefix"
	if [ "$command" = send-prefix ]; then
		bind_prefix_standin "$prefix"
	fi
}

# Undo setup_auto after the option is turned off and the config reloaded.
teardown_auto() {
	local prefix table command
	prefix=$(get_option @whichkey-prefix "")
	[ -n "$prefix" ] && [ "$(tmux show-option -gv prefix)" = None ] || return

	tmux set-option -g prefix "$prefix"
	for table in $PREFIX_TABLES; do
		binding_command command "$table" "$prefix"
		case $command in
		*auto.sh*) tmux unbind-key -T "$table" "$prefix" ;;
		esac
	done
	binding_command command prefix "$prefix"
	if is_prefix_standin "$prefix" "$command"; then
		tmux bind-key -N "Send the prefix key" -T prefix "$prefix" send-prefix
	fi
}

main() {
	if ! tmux_version_at_least 3 4; then
		tmux display-message "whichkey-tmux: requires tmux 3.4 or newer"
		return
	fi
	bind_menu_keys
	case $(get_option @whichkey-auto "$WK_DEFAULT_AUTO") in
	on | yes | 1) setup_auto ;;
	*) teardown_auto ;;
	esac
}

main
