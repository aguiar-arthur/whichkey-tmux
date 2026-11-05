# Queries to the tmux server.
#
# Tests can replace the server by defining a tmux() shell function after
# sourcing this file.

# Field separator for multi-field tmux output. Not whitespace, so empty
# fields (e.g. a binding without a note) survive `read`.
WK_SEP=$'\x1f'

# get_option <name> <default>: print a global option, or <default> if unset.
get_option() {
	local value
	value=$(tmux show-option -gqv "$1")
	printf '%s' "${value:-$2}"
}

# read_formats <client> <var> <format> [<var> <format>...]: expand every
# format for <client> in one round-trip and assign each result to its <var>.
read_formats() {
	local _client=$1 _format='' _vars=() _values=() _i
	shift
	while [ "$#" -ge 2 ]; do
		_vars+=("$1")
		_format=$_format${_format:+$WK_SEP}$2
		shift 2
	done
	IFS=$WK_SEP read -r -a _values <<EOF
$(tmux display-message -p -c "$_client" "$_format")
EOF
	for ((_i = 0; _i < ${#_vars[@]}; _i++)); do
		printf -v "${_vars[$_i]}" '%s' "${_values[$_i]}"
	done
}

# binding_command <var> <table> <key>: the command bound to <key> in
# <table>, or empty.
binding_command() {
	printf -v "$1" '%s' "$(tmux list-keys -T "$2" -F '#{key_command}' "$3" 2>/dev/null)"
}

# tmux_version_at_least <major> <minor>: succeeds if the running tmux is at
# least that version. Unparseable versions (e.g. "master") are assumed to be
# new enough.
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
