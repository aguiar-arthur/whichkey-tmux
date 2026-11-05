# The bindings of a key table, parsed once and shared by the menu and the
# popup. Requires tmux.sh, and WK_TMUX_VERSION set to the running tmux
# version (#{version}).

WK_BINDING_FORMAT="#{key_string}$WK_SEP#{key_note}$WK_SEP#{key_command}"

# A binding that only switches to another key table is a group.
WK_GROUP_RE='^switch-client -T ([^ ]+)$'

# list_bindings <var> <table> [<tmux option>...]: the bindings of <table>, one
# WK_BINDING_FORMAT line each. The tmux options (e.g. -L socket) select
# another server.
#
# Three ways, by tmux version:
#   3.8+  list-keys -T <table> -F
#   3.7   list-keys -F for every table, filtered: 3.7 shows a table with a
#         single binding in the status line instead of printing it
#   older list-keys has no -F: parse its plain output, and the notes from
#         list-keys -N
# WHICHKEY_TMUX_LIST=all or =plain forces one of the older ways, for tests.
list_bindings() {
	local _var=$1 _table=$2 _way=$WHICHKEY_TMUX_LIST _all _line _out='' _plain _notes
	shift 2
	if [ -z "$_way" ]; then
		if version_at_least "$WK_TMUX_VERSION" 3 8; then
			_way=table
		elif version_at_least "$WK_TMUX_VERSION" 3 7; then
			_way=all
		else
			_way=plain
		fi
	fi
	case $_way in
	table)
		printf -v "$_var" '%s' "$(tmux "$@" list-keys -T "$_table" -F "$WK_BINDING_FORMAT" 2>/dev/null)"
		;;
	all)
		_all=$(tmux "$@" list-keys -F "#{key_table}$WK_SEP$WK_BINDING_FORMAT" 2>/dev/null)
		while IFS= read -r _line; do
			case $_line in "$_table$WK_SEP"*) _out="$_out${_line#*"$WK_SEP"}"$'\n' ;; esac
		done <<<"$_all"
		printf -v "$_var" '%s' "${_out%$'\n'}"
		;;
	*)
		_plain=$(tmux "$@" list-keys -T "$_table" 2>/dev/null)
		_notes=$(tmux "$@" list-keys -N -P '' -T "$_table" 2>/dev/null)
		parse_list_keys "$_var" "$_plain" "$_notes"
		;;
	esac
}

# parse_list_keys <var> <plain> <notes>: WK_BINDING_FORMAT lines from the
# output of `list-keys -T table` and `list-keys -N -P '' -T table`:
#   bind-key -r -T prefix H       resize-pane -L
#   H       Resize the pane left
# list-keys escapes punctuation keys with a backslash (\; \#) or quotes
# them ("M-{"); the -N output does not.
parse_list_keys() {
	local _line _key _command _note _out='' _note_keys=() _notes=() _j=0
	# list-keys -N lists the bindings that have a note, in the same order as
	# list-keys: walk both together. A key is a single word, so `read`
	# splits it off the note.
	while IFS=' ' read -r _key _note; do
		[ -z "$_key" ] || {
			_note_keys+=("$_key")
			_notes+=("$_note")
		}
	done <<<"$3"
	while IFS= read -r _line; do
		case $_line in bind-key*-T\ *) ;; *) continue ;; esac
		# Skip the flags up to and including "-T <table>": the key follows.
		# (The key itself may be "-".)
		_line=${_line#*-T }
		_line=${_line#* }
		_line=${_line#"${_line%%[! ]*}"}
		_key=${_line%% *}
		_command=${_line#"$_key"}
		_command=${_command#"${_command%%[! ]*}"}
		case $_key in
		\\?) _key=${_key#\\} ;;
		\"?*\") _key=${_key:1:${#_key}-2} ;;
		esac
		_note=''
		if [ "${_note_keys[$_j]}" = "$_key" ]; then
			_note=${_notes[$_j]}
			_j=$((_j + 1))
		fi
		_out+="$_key$WK_SEP$_note$WK_SEP$_command"$'\n'
	done <<<"$2"
	printf -v "$1" '%s' "${_out%$'\n'}"
}

# lookup_command <var> <list> <key>: the command bound to <key> in <list>
# (list_bindings output), or empty. Looking the key up in the whole table,
# rather than with `list-keys -T <table> <key>`: tmux 3.7 shows a single
# result in the status line instead of printing it.
lookup_command() {
	local _list=$'\n'$2 _rest
	case $_list in
	*$'\n'"$3$WK_SEP"*)
		_rest=${_list#*$'\n'"$3$WK_SEP"}
		_rest=${_rest%%$'\n'*}
		printf -v "$1" '%s' "${_rest#*"$WK_SEP"}"
		;;
	*) printf -v "$1" '%s' '' ;;
	esac
}

# load_defaults <var> <table>: newline-delimited list of tmux's built-in
# bindings for <table>, one WK_BINDING_FORMAT line each, wrapped in newlines
# so callers can match whole lines with *"\n$line\n"*.
# Read from a throwaway config-less server once per tmux version, then cached.
# Tables tmux does not create itself have no defaults.
load_defaults() {
	local _dir _file _list
	case $2 in
	prefix | root | copy-mode | copy-mode-vi) ;;
	*)
		printf -v "$1" '\n'
		return
		;;
	esac
	_dir="${XDG_CACHE_HOME:-$HOME/.cache}/whichkey-tmux"
	_file="$_dir/defaults-$WK_TMUX_VERSION-$2"
	if [ ! -s "$_file" ]; then
		mkdir -p "$_dir"
		list_bindings _list "$2" -L "whichkey-defaults-$$" -f /dev/null
		[ -z "$_list" ] || { printf '%s\n' "$_list" >"$_file.$$" && mv "$_file.$$" "$_file"; }
		# The throwaway server exits on its own but leaves its socket behind.
		rm -f "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/whichkey-defaults-$$"
	fi
	printf -v "$1" '\n%s\n' "$(cat "$_file" 2>/dev/null)"
}

# load_bindings <table>: parse the bindings of <table> into the parallel
# arrays (bash 3.2 cannot return arrays):
#   WK_KEYS      key name
#   WK_NOTES     note (bind -N), or empty
#   WK_COMMANDS  command
#   WK_IS_USER   1 if it differs from tmux's built-in binding, else 0
#   WK_GROUP     for a group, the table it switches to, else empty
load_bindings() {
	local _defaults _list _line _key _note _command
	load_defaults _defaults "$1"
	list_bindings _list "$1"
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
	done <<<"$_list"
}

# binding_label <var> <index>: what to call a binding: its note, else its
# command. Groups get a "+" (unless the note has one) and fall back to the
# table name.
binding_label() {
	if [ -n "${WK_GROUP[$2]}" ]; then
		printf -v "$1" '+%s' "${WK_NOTES[$2]#+}"
		[ -n "${WK_NOTES[$2]}" ] || printf -v "$1" '+%s' "${WK_GROUP[$2]}"
	else
		printf -v "$1" '%s' "${WK_NOTES[$2]:-${WK_COMMANDS[$2]}}"
	fi
}
