#!/usr/bin/env bash
# Checks that the plugin is set up and working, and reviews your bindings:
# which have no note, and which replace one of tmux's. Run it in a tmux
# pane, or from tmux: prefix : run-shell <path>/scripts/doctor.sh
#
# Usage: doctor.sh
#
# Exits with the number of problems found; notes and replaced defaults are
# advice, not problems.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/quote.sh
source "$CURRENT_DIR/lib/quote.sh"
# shellcheck source=lib/options.sh
source "$CURRENT_DIR/lib/options.sh"
# shellcheck source=lib/tmux.sh
source "$CURRENT_DIR/lib/tmux.sh"
# shellcheck source=lib/bindings.sh
source "$CURRENT_DIR/lib/bindings.sh"
# shellcheck source=lib/automode.sh
source "$CURRENT_DIR/lib/automode.sh"
# shellcheck source=lib/debug.sh
source "$CURRENT_DIR/lib/debug.sh"

problems=0

good() { printf '  ✓ %s\n' "$*"; }
problem() {
	printf '  ✗ %s\n' "$*"
	problems=$((problems + 1))
}
info() { printf '  · %s\n' "$*"; }

# read_settings: the version and every option, in one call.
read_settings() {
	read_formats '' \
		WK_TMUX_VERSION '#{version}' \
		auto '#{@whichkey-auto}' \
		delay '#{@whichkey-delay}' \
		bound_key '#{@whichkey-bound-key}' \
		bound_root_key '#{@whichkey-bound-root-key}' \
		bound_search_key '#{@whichkey-bound-search-key}' \
		prefix_option '#{prefix}' \
		prefix '#{@whichkey-prefix}' \
		prefix2 '#{@whichkey-prefix2}' \
		debug '#{@whichkey-debug}'
	delay=${delay:-$WK_DEFAULT_DELAY}
}

# runs <table> <key> <script>: <key> in <table> still runs <script>.
runs() {
	local list command
	list_bindings list "$1"
	lookup_command command "$list" "$2"
	case $command in *"$CURRENT_DIR/$3"*) return 0 ;; esac
	return 1
}

# check_tool <name> <table> <key> <script>: report whether a key the plugin
# bound still runs its script.
check_tool() {
	[ -n "$3" ] || return 0
	if runs "$2" "$3" "$4"; then
		good "$1: $([ "$2" = prefix ] && echo "prefix ")$3"
	else
		problem "$1: $3 in the $2 table was bound to something else after the plugin loaded; load the plugin last in tmux.conf"
	fi
}

# check_auto: auto mode is set up as @whichkey-auto says.
check_auto() {
	local option key table missing
	case ${auto:-$WK_DEFAULT_AUTO} in
	on | yes | 1) ;;
	*)
		if [ "$prefix_option" = None ] && [ -n "$prefix" ]; then
			problem "auto mode is off but the prefix is still None: reload the config (tmux source-file ~/.tmux.conf)"
		else
			info "auto mode is off: set -g @whichkey-auto on for the popup after the prefix"
		fi
		return
		;;
	esac
	if [ "$prefix_option" != None ]; then
		problem "auto mode: the prefix option is $prefix_option, so the popup never shows. Something set it after the plugin loaded: load the plugin last in tmux.conf, then reload"
		return
	fi
	for option in prefix prefix2; do
		key=${!option}
		[ -n "$key" ] || continue
		missing=''
		for table in root copy-mode copy-mode-vi; do
			runs "$table" "$key" auto.sh || missing="$missing $table"
		done
		if [ -z "$missing" ]; then
			good "popup after $delay ms on $key ($option)"
		else
			problem "auto mode: $key no longer shows the popup in:$missing. Something rebound it after the plugin loaded: load the plugin last in tmux.conf"
		fi
	done
}

# review_bindings: list your bindings without a note, and those that
# replace one of tmux's, in prefix, root and every group reachable from
# them.
review_bindings() {
	local tables=(prefix root) seen=' prefix root ' t=0 table i key defaults
	local rest note bare='' replaced=''
	while [ "$t" -lt "${#tables[@]}" ]; do
		table=${tables[$t]}
		t=$((t + 1))
		load_bindings "$table"
		load_defaults defaults "$table"
		for ((i = 0; i < ${#WK_KEYS[@]}; i++)); do
			key=${WK_KEYS[$i]}
			if [ -n "${WK_GROUP[$i]}" ]; then
				case $seen in *" ${WK_GROUP[$i]} "*) ;; *)
					seen="$seen${WK_GROUP[$i]} "
					tables+=("${WK_GROUP[$i]}")
					;;
				esac
			fi
			[ "${WK_IS_USER[$i]}" = 1 ] || continue
			case $key in
			"$prefix" | "$prefix2") is_prefix_standin "$key" "${WK_COMMANDS[$i]}" && continue ;;
			esac
			case ${WK_COMMANDS[$i]} in *"$CURRENT_DIR/"*) continue ;; esac
			if [ -z "${WK_NOTES[$i]}" ] && [ -z "${WK_GROUP[$i]}" ]; then
				printf -v bare '%s    %-14s %-8s %s\n' "$bare" "$table" "$key" "${WK_COMMANDS[$i]:0:60}"
			fi
			case $defaults in
			*$'\n'"$key$WK_SEP"*)
				rest=${defaults#*$'\n'"$key$WK_SEP"}
				note=${rest%%"$WK_SEP"*}
				printf -v replaced '%s    %-14s %-8s was: %s\n' "$replaced" "$table" "$key" "${note:-${rest#*"$WK_SEP"}}"
				;;
			esac
		done
	done
	echo
	echo "Your bindings without a note (bind -N \"What it does\" ...):"
	if [ -n "$bare" ]; then
		printf '%s' "$bare"
		echo "    Labels fall back to the command; a note reads better in the popup."
	else
		good "every binding of yours has a note"
	fi
	echo
	echo "Your bindings that replace one of tmux's:"
	if [ -n "$replaced" ]; then
		printf '%s' "$replaced"
	else
		good "none"
	fi
}

main() {
	read_settings
	echo "whichkey-tmux doctor"
	echo
	echo "Setup:"
	if ! version_at_least "$WK_TMUX_VERSION" 3 4; then
		problem "tmux $WK_TMUX_VERSION: the plugin needs tmux 3.4 or newer"
		return
	fi
	good "tmux $WK_TMUX_VERSION, bash $BASH_VERSION"
	if [ -z "$bound_key" ] && [ -z "$bound_root_key" ]; then
		problem "the plugin has not run in this server: add run-shell <path>/whichkey.tmux to the end of tmux.conf and reload"
		return
	fi
	check_tool catalog prefix "$bound_key" menu.sh
	check_tool catalog root "$bound_root_key" menu.sh
	check_tool search prefix "$bound_search_key" search.sh
	check_auto
	case $debug in
	on | yes | 1) info "debug log on: $WK_DEBUG_LOG (turn @whichkey-debug off when done)" ;;
	esac
	review_bindings
}

main
echo
if [ "$problems" -eq 0 ]; then
	echo "No problems found."
else
	echo "$problems problem(s) found."
fi
exit "$problems"
