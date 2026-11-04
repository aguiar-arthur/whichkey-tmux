#!/usr/bin/env bash
# Entry point: run by TPM, or by `run-shell /path/to/whichkey.tmux`.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/helpers.sh
source "$CURRENT_DIR/scripts/helpers.sh"

# Tables where the prefix key has to be bound by hand once the prefix option
# is None: root, plus the copy-mode tables, which replace root in copy mode.
PREFIX_TABLES="root copy-mode copy-mode-vi"

# The prefix key the user configured. While auto mode is on the prefix option
# is None, so on a config reload fall back to the key we saved.
user_prefix() {
	local prefix
	prefix=$(tmux show-option -gv prefix)
	if [ "$prefix" = None ]; then
		get_option @whichkey-prefix ""
	else
		tmux set-option -g @whichkey-prefix "$prefix"
		printf '%s' "$prefix"
	fi
}

# tmux switches to the prefix table internally, before any key binding, so
# there is no event to hang a timer on. Instead, turn the prefix option off
# and bind the key ourselves: switch to the prefix table, bump a sequence
# number, note the state and check back after the delay (see scripts/auto.sh).
setup_auto() {
	local prefix delay seconds auto run trigger table
	prefix=$(user_prefix)
	[ -n "$prefix" ] || return

	delay=$(get_option @whichkey-delay 200)
	printf -v seconds '%d.%03d' $((delay / 1000)) $((delay % 1000))
	sh_quote auto "$CURRENT_DIR/scripts/auto.sh"
	format_escape auto "$auto"
	tmux_quote run "$auto '#{client_name}' '#{pane_id}' '#{@whichkey-seq}' '$WK_STATE_FORMAT'"
	trigger="switch-client -T prefix ; set-option -gF @whichkey-seq '#{e|+:#{@whichkey-seq},1}' ; run-shell -b -d $seconds $run"

	tmux set-option -g prefix None
	for table in $PREFIX_TABLES; do
		tmux bind-key -T "$table" "$prefix" "$trigger"
	done
	# send-prefix sends the prefix option, which is now None.
	if [ "$(tmux list-keys -T prefix -F '#{key_command}' "$prefix" 2>/dev/null)" = send-prefix ]; then
		tmux bind-key -N "Send the prefix key" -T prefix "$prefix" send-keys "$prefix"
	fi
}

# Undo setup_auto after the option is turned off and the config reloaded.
teardown_auto() {
	local prefix table
	prefix=$(get_option @whichkey-prefix "")
	[ -n "$prefix" ] && [ "$(tmux show-option -gv prefix)" = None ] || return

	tmux set-option -g prefix "$prefix"
	for table in $PREFIX_TABLES; do
		case $(tmux list-keys -T "$table" -F '#{key_command}' "$prefix" 2>/dev/null) in
		*auto.sh*) tmux unbind-key -T "$table" "$prefix" ;;
		esac
	done
	if [ "$(tmux list-keys -T prefix -F '#{key_command}' "$prefix" 2>/dev/null)" = "send-keys $prefix" ]; then
		tmux bind-key -N "Send the prefix key" -T prefix "$prefix" send-prefix
	fi
}

main() {
	if ! tmux_version_at_least 3 4; then
		tmux display-message "whichkey-tmux: requires tmux 3.4 or newer"
		return
	fi

	local menu open key root_key
	sh_quote menu "$CURRENT_DIR/scripts/menu.sh"
	format_escape menu "$menu"
	tmux_quote open "$menu '#{client_name}' '#{pane_id}' prefix"
	open="run-shell -b $open"
	key=$(get_option @whichkey-key Space)
	root_key=$(get_option @whichkey-root-key "")

	tmux bind-key -N "Show key bindings" "$key" "$open"
	if [ -n "$root_key" ]; then
		tmux bind-key -n -N "Show key bindings" "$root_key" "$open"
	fi

	case $(get_option @whichkey-auto off) in
	on | yes | 1) setup_auto ;;
	*) teardown_auto ;;
	esac
}

main
