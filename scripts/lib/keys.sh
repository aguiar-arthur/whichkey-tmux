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

# decode_key <var> <byte> [<rest>]: tmux key name for terminal input.
# <byte> is the first byte as two hex digits; after an Escape (1b), <rest> is
# what followed it. Sets <var> empty for input with no key name, and for a
# lone Escape.
decode_key() {
	local _key= _mod= _letters=abcdefghijklmnopqrstuvwxyz
	case $2 in
	1b)
		case $3 in
		'') ;;
		\[A | OA) _key=Up ;;
		\[B | OB) _key=Down ;;
		\[C | OC) _key=Right ;;
		\[D | OD) _key=Left ;;
		\[H | OH) _key=Home ;;
		\[F | OF) _key=End ;;
		\[5~) _key=PPage ;;
		\[6~) _key=NPage ;;
		\[2~) _key=IC ;;
		\[3~) _key=DC ;;
		\[Z) _key=BTab ;;
		\[1\;[2-8][ABCD])
			case ${3:3:1} in
			2) _mod=S- ;; 3) _mod=M- ;; 4) _mod=S-M- ;; 5) _mod=C- ;;
			6) _mod=C-S- ;; 7) _mod=C-M- ;; 8) _mod=C-S-M- ;;
			esac
			case ${3:4:1} in
			A) _key=${_mod}Up ;; B) _key=${_mod}Down ;;
			C) _key=${_mod}Right ;; D) _key=${_mod}Left ;;
			esac
			;;
		?) _key="M-$3" ;;
		esac
		;;
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
		_key="C-${_letters:$((16#$2 - 1)):1}"
		;;
	[2-7][0-9a-f]) printf -v _key "\\x$2" ;;
	esac
	printf -v "$1" '%s' "$_key"
}
