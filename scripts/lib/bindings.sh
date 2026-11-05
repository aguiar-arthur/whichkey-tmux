# The bindings of a key table, parsed once and shared by the menu and the
# popup. Requires tmux.sh.

WK_BINDING_FORMAT="#{key_string}$WK_SEP#{key_note}$WK_SEP#{key_command}"

# A binding that only switches to another key table is a group.
WK_GROUP_RE='^switch-client -T ([^ ]+)$'

# load_defaults <var> <version> <table>: newline-delimited list of tmux's
# built-in bindings for <table>, one WK_BINDING_FORMAT line each, wrapped in
# newlines so callers can match whole lines with *"\n$line\n"*.
# Read from a throwaway config-less server once per tmux version, then cached.
# Tables tmux does not create itself have no defaults.
load_defaults() {
	local _dir _file
	case $3 in
	prefix | root | copy-mode | copy-mode-vi) ;;
	*)
		printf -v "$1" '\n'
		return
		;;
	esac
	_dir="${XDG_CACHE_HOME:-$HOME/.cache}/whichkey-tmux"
	_file="$_dir/defaults-$2-$3"
	if [ ! -s "$_file" ]; then
		mkdir -p "$_dir"
		tmux -L "whichkey-defaults-$$" -f /dev/null list-keys -T "$3" \
			-F "$WK_BINDING_FORMAT" >"$_file.$$" 2>/dev/null &&
			mv "$_file.$$" "$_file"
		# The throwaway server exits on its own but leaves its socket behind.
		rm -f "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/whichkey-defaults-$$"
	fi
	printf -v "$1" '\n%s\n' "$(cat "$_file" 2>/dev/null)"
}

# load_bindings <table> <version>: parse the bindings of <table> into the
# parallel arrays (bash 3.2 cannot return arrays):
#   WK_KEYS      key name
#   WK_NOTES     note (bind -N), or empty
#   WK_COMMANDS  command
#   WK_IS_USER   1 if it differs from tmux's built-in binding, else 0
#   WK_GROUP     for a group, the table it switches to, else empty
load_bindings() {
	local _defaults _line _key _note _command
	load_defaults _defaults "$2" "$1"
	WK_KEYS=() WK_NOTES=() WK_COMMANDS=() WK_IS_USER=() WK_GROUP=()
	while IFS= read -r _line; do
		IFS=$WK_SEP read -r _key _note _command <<<"$_line"
		[ -n "$_key" ] || continue
		WK_KEYS+=("$_key")
		WK_NOTES+=("$_note")
		WK_COMMANDS+=("$_command")
		case $_defaults in
		*"
$_line
"*) WK_IS_USER+=(0) ;;
		*) WK_IS_USER+=(1) ;;
		esac
		if [[ $_command =~ $WK_GROUP_RE ]]; then
			WK_GROUP+=("${BASH_REMATCH[1]}")
		else
			WK_GROUP+=("")
		fi
	done <<EOF
$(tmux list-keys -T "$1" -F "$WK_BINDING_FORMAT")
EOF
}

# binding_label <var> <index>: what to call a binding: its note, else its
# command. Groups get a "+" and fall back to the table name.
binding_label() {
	if [ -n "${WK_GROUP[$2]}" ]; then
		printf -v "$1" '+%s' "${WK_NOTES[$2]:-${WK_GROUP[$2]}}"
	else
		printf -v "$1" '%s' "${WK_NOTES[$2]:-${WK_COMMANDS[$2]}}"
	fi
}
