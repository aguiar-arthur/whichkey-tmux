# Matching what is typed into the search against a binding. Pure.

# fuzzy_pattern <var> <query>: a pattern that matches text containing the
# characters of <query> in order, with anything between them ("sw" matches
# "Split window"). Use it unquoted in [[ $text == $pattern ]], under
# nocasematch to ignore case.
fuzzy_pattern() {
	local _pattern='*' _i
	for ((_i = 0; _i < ${#2}; _i++)); do
		# A backslash makes each character literal, * and [ included.
		_pattern="$_pattern\\${2:_i:1}*"
	done
	printf -v "$1" '%s' "$_pattern"
}

# match_rank <var> <text> <query> <pattern>: 0 if <text> contains <query>,
# 1 if it only matches <pattern> (from fuzzy_pattern), else empty. Ignores
# case.
match_rank() {
	local _rank=''
	shopt -s nocasematch
	# shellcheck disable=SC2053 # $4 is a pattern on purpose
	if [[ $2 == *"$3"* ]]; then
		_rank=0
	elif [[ $2 == $4 ]]; then
		_rank=1
	fi
	shopt -u nocasematch
	printf -v "$1" '%s' "$_rank"
}
