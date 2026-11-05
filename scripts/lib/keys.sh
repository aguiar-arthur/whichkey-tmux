# Key names: decoding terminal input, and how to send a key to tmux.

# key_hex <var> <key>: if <key> is a single ASCII character, set <var> to
# its code as two hex digits. Such keys are sent with `send-keys -H`, because
# punctuation such as ; " or { cannot be passed reliably as a bare argument
# or quoted for the tmux command parser.
key_hex() {
	local _code
	[ "${#2}" -eq 1 ] || return 1
	printf -v _code '%d' "'$2"
	# bash 3.2 gives the first byte of a multibyte character as a negative.
	[ "$_code" -ge 0 ] && [ "$_code" -lt 128 ] || return 1
	printf -v "$1" '%02x' "$_code"
}

# needs_rest <byte>: succeeds if more bytes follow <byte> as part of the same
# key: an escape sequence, or a multibyte UTF-8 character.
needs_rest() {
	case $1 in
	1b | c[2-9a-f] | d[0-9a-f] | e[0-9a-f] | f[0-4]) return 0 ;;
	esac
	return 1
}

# decode_key <var> <byte> [<rest>]: tmux key name for terminal input, as
# tmux encodes keys for a popup. <byte> is the first byte as two hex digits,
# <rest> the bytes that followed it (see needs_rest). Sets <var> empty for a
# lone Escape and for input with no key name.
decode_key() {
	local _key=
	case $2 in
	1b) decode_escape _key "$3" ;;
	0d) _key=Enter ;;
	09) _key=Tab ;;
	7f) _key=BSpace ;;
	20) _key=Space ;;
	00) _key=C-Space ;;
	1c) _key='C-\' ;;
	1d) _key='C-]' ;;
	1e) _key='C-^' ;;
	1f) _key=C-_ ;;
	0[1-9a-f] | 1[0-9a])
		# Control characters 0x01-0x1a are C-a..C-z.
		_key=abcdefghijklmnopqrstuvwxyz
		_key="C-${_key:$((16#$2 - 1)):1}"
		;;
	[2-7][0-9a-f]) printf -v _key "\\x$2" ;;
	c[2-9a-f] | d[0-9a-f] | e[0-9a-f] | f[0-4])
		# A UTF-8 character: tmux names it by the character itself.
		[ -n "$3" ] && printf -v _key "\\x$2%s" "$3"
		;;
	esac
	printf -v "$1" '%s' "$_key"
}

# decode_escape <var> <rest>: key name for Escape followed by <rest>.
decode_escape() {
	local _inner= _hex _final _params _code= _mod=1 _base=
	case $2 in
	'') ;; # A lone Escape.
	?)
		# Escape then one key is that key with Meta: M-a, C-M-a, M-Enter.
		printf -v _hex '%02x' "'$2"
		decode_key _inner "$_hex"
		case $_inner in
		'') ;;
		C-*) _base="C-M-${_inner#C-}" ;;
		*) _base="M-$_inner" ;;
		esac
		;;
	\[Z) _base=BTab ;;
	O[ABCDHFPQRS] | \[*)
		# SS3 (O<final>) or CSI ([<code>;<modifiers><final>).
		_final=${2: -1}
		_params=${2#?}
		_params=${_params%?}
		case $_params in
		*\;*)
			_code=${_params%%;*}
			_mod=${_params#*;}
			;;
		*) _code=$_params ;;
		esac
		case $_final in
		A) _base=Up ;; B) _base=Down ;; C) _base=Right ;; D) _base=Left ;;
		H) _base=Home ;; F) _base=End ;;
		P) _base=F1 ;; Q) _base=F2 ;; R) _base=F3 ;; S) _base=F4 ;;
		\~)
			case $_code in
			1 | 7) _base=Home ;; 2) _base=IC ;; 3) _base=DC ;;
			4 | 8) _base=End ;; 5) _base=PPage ;; 6) _base=NPage ;;
			11) _base=F1 ;; 12) _base=F2 ;; 13) _base=F3 ;; 14) _base=F4 ;;
			15) _base=F5 ;; 17) _base=F6 ;; 18) _base=F7 ;; 19) _base=F8 ;;
			20) _base=F9 ;; 21) _base=F10 ;; 23) _base=F11 ;; 24) _base=F12 ;;
			esac
			_code=
			;;
		esac
		# Letter finals take no code other than 1 (the "1;5A" form).
		case $_code in '' | 1) ;; *) _base= ;; esac
		# Modifiers are 1 + a bitmask: 1 shift, 2 meta, 4 ctrl.
		case $_mod in
		[1-8])
			_mod=$((_mod - 1))
			[ $((_mod & 1)) -eq 0 ] || _base="S-$_base"
			[ $((_mod & 2)) -eq 0 ] || _base="M-$_base"
			[ $((_mod & 4)) -eq 0 ] || _base="C-$_base"
			;;
		*) _base= ;;
		esac
		case $_base in *-) _base= ;; esac
		;;
	esac
	printf -v "$1" '%s' "$_base"
}
