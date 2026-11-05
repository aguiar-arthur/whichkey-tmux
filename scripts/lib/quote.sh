# Quoting and escaping: pure string functions, no tmux calls.
#
# Everything under lib/ must stay compatible with bash 3.2 (macOS /bin/bash):
# no associative arrays, no mapfile, no ${var,,}. Helpers that build strings
# assign to the variable named by their first argument (via printf -v)
# instead of printing, so hot loops avoid forking a subshell per call; their
# own locals start with "_" so they never shadow the caller's variable.

# format_escape <var> <string>: escape so a tmux format expansion leaves the
# string unchanged.
format_escape() {
	printf -v "$1" '%s' "${2//\#/##}"
}

# tmux_quote <var> <string>: quote as one argument for the tmux command parser.
tmux_quote() {
	local _s
	case $2 in
	*"'"*)
		_s=${2//\\/\\\\}
		_s=${_s//\"/\\\"}
		_s=${_s//\$/\\\$}
		printf -v "$1" '"%s"' "$_s"
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
	# Pattern and replacement in variables: bash 3.2 keeps the backslashes
	# of \' inside a quoted ${//}.
	local _sq="'" _esc="'\\''"
	printf -v "$1" "'%s'" "${2//$_sq/$_esc}"
}

# truncate_label <var> <string> <width> <ellipsis>: cut <string> to <width>
# characters, ending in <ellipsis> if it was cut.
truncate_label() {
	if [ "${#2}" -gt "$3" ]; then
		printf -v "$1" '%s%s' "${2:0:$(($3 - ${#4}))}" "$4"
	else
		printf -v "$1" '%s' "$2"
	fi
}
