# Shared helpers. Must stay compatible with bash 3.2 (macOS /bin/bash):
# no associative arrays, no mapfile, no ${var,,}.
#
# Helpers that build strings assign to the variable named by their first
# argument (via printf -v) instead of printing, so hot loops avoid forking a
# subshell per call.

# Field separator for list-keys -F output. Not whitespace, so empty fields
# (e.g. a binding without a note) survive `read`.
WK_SEP=$'\x1f'

# What a key binding is likely to change: expanded when the prefix is pressed
# and again before showing the popup, to tell whether a key ran in between.
WK_STATE_FORMAT='#{session_id}:#{window_id}:#{pane_id}:#{window_layout}'

# get_option <name> <default>
get_option() {
	local value
	value=$(tmux show-option -gqv "$1")
	printf '%s' "${value:-$2}"
}

# format_escape <var> <string>: escape so a tmux format expansion leaves the
# string unchanged.
format_escape() {
	printf -v "$1" '%s' "${2//\#/##}"
}

# tmux_quote <var> <string>: quote as one argument for the tmux command parser.
tmux_quote() {
	local s
	case $2 in
	*"'"*)
		s=${2//\\/\\\\}
		s=${s//\"/\\\"}
		s=${s//\$/\\\$}
		printf -v "$1" '"%s"' "$s"
		;;
	*) printf -v "$1" "'%s'" "$2" ;;
	esac
}

# argv_escape <var> <string>: the tmux CLI treats an argument ending in ";"
# as a command separator; escape that so it is passed through literally.
argv_escape() {
	case $2 in
	*';') printf -v "$1" '%s\\;' "${2%;}" ;;
	*) printf -v "$1" '%s' "$2" ;;
	esac
}

# sh_quote <var> <string>: quote as one argument for /bin/sh.
sh_quote() {
	printf -v "$1" "'%s'" "${2//\'/\'\\\'\'}"
}

# load_defaults <var> <version> <table>: newline-delimited list of tmux's
# built-in bindings for <table>, one "key SEP note SEP command" per line,
# wrapped in newlines so callers can match whole lines with *"\n$line\n"*.
# Read from a throwaway config-less server once per tmux version, then cached.
# Tables tmux does not create itself have no defaults.
load_defaults() {
	local dir file
	case $3 in
	prefix | root | copy-mode | copy-mode-vi) ;;
	*)
		printf -v "$1" '\n'
		return
		;;
	esac
	dir="${XDG_CACHE_HOME:-$HOME/.cache}/whichkey-tmux"
	file="$dir/defaults-$2-$3"
	if [ ! -s "$file" ]; then
		mkdir -p "$dir"
		tmux -L "whichkey-defaults-$$" -f /dev/null list-keys -T "$3" \
			-F "#{key_string}$WK_SEP#{key_note}$WK_SEP#{key_command}" >"$file.$$" 2>/dev/null &&
			mv "$file.$$" "$file"
		# The throwaway server exits on its own but leaves its socket behind.
		rm -f "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/whichkey-defaults-$$"
	fi
	printf -v "$1" '\n%s\n' "$(cat "$file" 2>/dev/null)"
}

# Succeeds if the running tmux is at least <major>.<minor>. Unparseable
# versions (e.g. "master") are assumed to be new enough.
tmux_version_at_least() {
	local version major minor
	version=$(tmux display-message -p '#{version}')
	version=${version#next-}
	major=${version%%.*}
	minor=${version#*.}
	minor=${minor%%[!0-9]*}
	case $major$minor in
	'' | *[!0-9]*) return 0 ;;
	esac
	[ "$major" -gt "$1" ] || { [ "$major" -eq "$1" ] && [ "$minor" -ge "$2" ]; }
}
