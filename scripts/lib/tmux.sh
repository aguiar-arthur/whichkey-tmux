# Queries to the tmux server.
#
# Tests can replace the server by defining a tmux() shell function after
# sourcing this file.

# Field separator for multi-field tmux output. Not whitespace, so empty
# fields (e.g. a binding without a note) survive `read`.
WK_SEP=$'\x1f'

# read_formats <client> <var> <format> [<var> <format>...]: expand every
# format for <client> (empty: no client) in one round-trip and assign each
# result to its <var>.
read_formats() {
	local _client=$1 _format='' _vars=() _values=() _i _out
	shift
	while [ "$#" -ge 2 ]; do
		_vars+=("$1")
		_format=$_format${_format:+$WK_SEP}$2
		shift 2
	done
	if [ -n "$_client" ]; then
		_out=$(tmux display-message -p -c "$_client" "$_format")
	else
		_out=$(tmux display-message -p "$_format")
	fi
	# Before tmux 3.7, display-message -p escapes control characters, so the
	# separator arrives as the text \037.
	_out=${_out//\\037/$WK_SEP}
	IFS=$WK_SEP read -r -a _values <<<"$_out"
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
