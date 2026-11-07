# Reading keys inside a popup, which runs on its own pseudo-terminal.
# Requires keys.sh.

# raw_input: no echo, no line buffering, and a read waits for one byte.
# opost keeps "\n" moving to the start of the next line.
raw_input() {
	stty raw -echo opost min 1 time 0
}

# read_byte: one raw byte as two hex digits. stty min/time control how long
# dd waits.
read_byte() {
	dd bs=1 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n'
}

# read_key <var>: wait for one key and set <var> to its tmux name (empty for
# a lone Escape or input with no name). Call raw_input first.
read_key() {
	local _byte _rest=''
	_byte=$(read_byte)
	if needs_rest "$_byte"; then
		# The rest of a key arrives together; a lone Escape gets nothing
		# more within a tenth of a second.
		stty min 0 time 1
		read_rest _rest "$_byte"
		stty min 1 time 0
	fi
	decode_key "$1" "$_byte" "$_rest"
}

# utf8_left <var> <byte>: how many bytes follow <byte> in its UTF-8
# character (0 if it does not start one).
utf8_left() {
	case $2 in
	c[2-9a-f] | d[0-9a-f]) printf -v "$1" 1 ;;
	e[0-9a-f]) printf -v "$1" 2 ;;
	f[0-4]) printf -v "$1" 3 ;;
	*) printf -v "$1" 0 ;;
	esac
}

# read_rest <var> <byte>: the bytes that complete the key starting with
# <byte> (see needs_rest), and no more: keys typed quickly (a held arrow)
# arrive together, and the next one must stay for the next read_key.
read_rest() {
	local _out='' _hex _left=0 _csi=0 _i
	# SC2059: \xNN in a printf format decodes a byte.
	# shellcheck disable=SC2059
	if [ "$2" = 1b ]; then
		_hex=$(read_byte)
		case $_hex in
		'') ;; # A lone Escape.
		5b) _csi=1 ;;
		4f) _left=1 ;; # SS3: O and one byte.
		*) utf8_left _left "$_hex" ;;
		esac
		[ -z "$_hex" ] || printf -v _out "\x$_hex"
	else
		utf8_left _left "$2"
	fi
	# CSI: parameters, then a final byte in 0x40-0x7e.
	for ((_i = 0; _csi && _i < 16; _i++)); do
		_hex=$(read_byte)
		[ -n "$_hex" ] || break
		# shellcheck disable=SC2059
		printf -v _out "%s\x$_hex" "$_out"
		case $_hex in [4-6][0-9a-f] | 7[0-9a-e]) break ;; esac
	done
	while [ "$_left" -gt 0 ]; do
		_hex=$(read_byte)
		[ -n "$_hex" ] || break
		# shellcheck disable=SC2059
		printf -v _out "%s\x$_hex" "$_out"
		_left=$((_left - 1))
	done
	printf -v "$1" '%s' "$_out"
}
