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

# version_at_least <version> <major> <minor>: succeeds if a tmux version
# (#{version}, e.g. 3.5a or next-3.9) is at least <major>.<minor>.
# Unparseable versions (e.g. "master") are assumed to be new enough.
version_at_least() {
	local _version=${1#next-} _major _minor
	_major=${_version%%.*}
	_minor=${_version#*.}
	_minor=${_minor%%[!0-9]*}
	case $_major$_minor in
	'' | *[!0-9]*) return 0 ;;
	esac
	[ "$_major" -gt "$2" ] || { [ "$_major" -eq "$2" ] && [ "$_minor" -ge "$3" ]; }
}
