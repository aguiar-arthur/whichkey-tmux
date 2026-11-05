#!/usr/bin/env bash
# Entry point: run by TPM, or by `run-shell /path/to/whichkey.tmux`, on
# every config (re)load. Running it twice must give the same result as once.
#
# Every tmux call costs a few milliseconds and the plugin loads with tmux, so
# settings are read in one call and changes are queued and sent in one call
# (see queue). In a tmux command sequence a failing command stops the rest,
# so commands that commit a change (prefix None) are queued after those that
# prepare it: if a binding fails, the prefix is left alone.

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

QUEUE=()

# queue <arg>...: add one tmux command to QUEUE.
queue() {
	local _arg
	[ "${#QUEUE[@]}" -eq 0 ] || QUEUE+=(';')
	for _arg in "$@"; do
		# An argument ending in ";" would end the command.
		argv_escape _arg "$_arg"
		QUEUE+=("$_arg")
	done
}

# run_queue: send QUEUE to tmux in one call, then empty it.
run_queue() {
	[ "${#QUEUE[@]}" -eq 0 ] || tmux "${QUEUE[@]}"
	QUEUE=()
}

# read_settings: the tmux version and every option, in one call.
read_settings() {
	read_formats '' \
		WK_TMUX_VERSION '#{version}' \
		debug '#{@whichkey-debug}' \
		auto '#{@whichkey-auto}' \
		delay '#{@whichkey-delay}' \
		menu_key '#{@whichkey-key}' \
		root_key '#{@whichkey-root-key}' \
		bound_key '#{@whichkey-bound-key}' \
		bound_root_key '#{@whichkey-bound-root-key}' \
		search_key '#{@whichkey-search-key}' \
		bound_search_key '#{@whichkey-bound-search-key}' \
		current_prefix '#{prefix}' \
		current_prefix2 '#{prefix2}' \
		saved_prefix '#{@whichkey-prefix}' \
		saved_prefix2 '#{@whichkey-prefix2}'
	menu_key=${menu_key:-$WK_DEFAULT_KEY}
	search_key=${search_key:-$WK_DEFAULT_SEARCH_KEY}
	delay=${delay:-$WK_DEFAULT_DELAY}
}

# table_command <var> <table> <key>: the command bound to <key> in <table>,
# listing each table at most once per load.
table_command() {
	local _cache="TABLE_${2//-/_}"
	if [ -z "${!_cache+set}" ]; then
		list_bindings "$_cache" "$2"
	fi
	lookup_command "$1" "${!_cache}" "$3"
}

# script_command <var> <script>: tmux command that runs scripts/<script>
# for the client and pane where the key was pressed.
script_command() {
	local _script
	sh_quote _script "$CURRENT_DIR/scripts/$2"
	format_escape _script "$_script"
	tmux_quote _script "$_script '#{client_name}' '#{pane_id}'"
	printf -v "$1" 'run-shell -b %s' "$_script"
}

# bind_tool <table> <key> <bound> <option> <note> <script>: bind <key> in
# <table> to run <script>, and remember it in <option>. <bound>, the key
# remembered before, is unbound if it changed and still runs <script>. An
# empty <key> binds nothing.
bind_tool() {
	local command
	if [ -n "$3" ] && [ "$3" != "$2" ]; then
		table_command command "$1" "$3"
		case $command in
		*"$6"*) queue unbind-key -T "$1" "$3" ;;
		esac
	fi
	if [ -n "$2" ]; then
		script_command command "$6"
		queue bind-key -T "$1" -N "$5" "$2" "$command"
		queue set-option -g "$4" "$2"
	else
		queue set-option -gu "$4"
	fi
}

# bind_menu_keys: @whichkey-key in the prefix table (and @whichkey-root-key,
# if set, in the root table) opens the catalog menu; @whichkey-search-key,
# if set, opens the search.
bind_menu_keys() {
	bind_tool prefix "$menu_key" "$bound_key" @whichkey-bound-key "Show key bindings" menu.sh
	bind_tool root "$root_key" "$bound_root_key" @whichkey-bound-root-key "Show key bindings" menu.sh
	bind_tool prefix "$search_key" "$bound_search_key" @whichkey-bound-search-key "Search key bindings" search.sh
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
# would have handled it as <option>, and replace its send-prefix binding.
claim_key() {
	local table command send_prefix
	for table in $PREFIX_TABLES; do
		queue bind-key -T "$table" "$1" "$3"
	done
	table_command command prefix "$1"
	send_prefix_command send_prefix "$2"
	if [ "$command" = "$send_prefix" ]; then
		# send-prefix sends the option, which is about to be None.
		queue bind-key -N "Send the prefix key" -T prefix "$1" send-keys "$1"
	fi
}

# release_key <key> <option>: undo claim_key.
release_key() {
	local table command send_prefix
	for table in $PREFIX_TABLES; do
		table_command command "$table" "$1"
		case $command in
		*auto.sh*) queue unbind-key -T "$table" "$1" ;;
		esac
	done
	table_command command prefix "$1"
	if is_prefix_standin "$1" "$command"; then
		send_prefix_command send_prefix "$2"
		# shellcheck disable=SC2086 # "send-prefix -2" is two arguments
		queue bind-key -N "Send the prefix key" -T prefix "$1" $send_prefix
	fi
}

# tmux switches to the prefix table internally, before any key binding, so
# there is no event to hang a timer on. Instead, turn the prefix options off
# and bind their keys ourselves.
setup_auto() {
	local trigger option current saved key claimed=''
	prefix_trigger trigger "$delay"
	for option in $PREFIX_OPTIONS; do
		current="current_$option" saved="saved_$option"
		current=${!current} saved=${!saved}
		if [ "$current" = None ]; then
			# Already ours (a reload): use the key we saved.
			key=$saved
		else
			# The config set the key. If it changed, give the old one back.
			if [ -n "$saved" ] && [ "$saved" != "$current" ]; then
				release_key "$saved" "$option"
			fi
			key=$current
			queue set-option -g "@whichkey-$option" "$key"
		fi
		[ -n "$key" ] || continue
		claim_key "$key" "$option" "$trigger"
		claimed="$claimed $option"
	done
	# Only now, after every binding above succeeded.
	for option in $claimed; do
		queue set-option -g "$option" None
	done
	queue set-hook -g "$WK_DETACH_HOOK" "set-option -gqu '@whichkey-seq-#{hook_client}'"
	run_queue
}

# Undo setup_auto after the option is turned off and the config reloaded.
teardown_auto() {
	local option current saved
	for option in $PREFIX_OPTIONS; do
		current="current_$option" saved="saved_$option"
		current=${!current} saved=${!saved}
		[ -n "$saved" ] && [ "$current" = None ] || continue
		# The prefix first: whatever happens next, it works again.
		queue set-option -g "$option" "$saved"
		release_key "$saved" "$option"
	done
	[ "${#QUEUE[@]}" -eq 0 ] || queue set-hook -gu "$WK_DETACH_HOOK"
	run_queue
}

# apply_debug_option: start or stop the debug log, starting it afresh once it
# passes 10 MB. The log holds the commands of the user's bindings, so only
# the user can read it.
apply_debug_option() {
	case $debug in
	on | yes | 1)
		mkdir -p "$WK_DEBUG_DIR"
		if [ "$(wc -c <"$WK_DEBUG_LOG" 2>/dev/null || echo 0)" -gt 10485760 ]; then
			rm -f "$WK_DEBUG_LOG"
		fi
		(umask 077 && : >>"$WK_DEBUG_LOG" && : >"$WK_DEBUG_FLAG")
		chmod 600 "$WK_DEBUG_LOG"
		;;
	*) rm -f "$WK_DEBUG_FLAG" ;;
	esac
	# shellcheck disable=SC2119 # no arguments to log
	debug_init
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

main() {
	read_settings
	apply_debug_option
	if ! version_at_least "$WK_TMUX_VERSION" 3 4; then
		tmux display-message "whichkey-tmux: requires tmux 3.4 or newer"
		return
	fi
	# Two calls: a bad @whichkey-key must not stop auto mode, and the other
	# way round.
	bind_menu_keys
	run_queue
	case ${auto:-$WK_DEFAULT_AUTO} in
	on | yes | 1) setup_auto ;;
	*) teardown_auto ;;
	esac
	warm_defaults_cache
}

# Run when executed (TPM, run-shell); tests source this file for its
# functions.
[ "${BASH_SOURCE[0]}" != "$0" ] || main
