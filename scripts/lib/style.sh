# tmux styles ("fg=magenta,bold") as terminal escape sequences, for the
# popup grid, which is drawn by a shell script rather than by tmux.

# colour_sgr <var> <colour> <base>: SGR parameters for a tmux colour, with
# <base> 30 for foreground or 40 for background. Empty if not understood.
colour_sgr() {
	local _name=$2 _base=$3 _n= _hex
	# brightred etc. are the basic colours 60 higher.
	case $_name in bright*)
		_name=${_name#bright}
		_base=$((_base + 60))
		;;
	esac
	case $_name in
	black) _n=$_base ;; red) _n=$((_base + 1)) ;; green) _n=$((_base + 2)) ;;
	yellow) _n=$((_base + 3)) ;; blue) _n=$((_base + 4)) ;; magenta) _n=$((_base + 5)) ;;
	cyan) _n=$((_base + 6)) ;; white) _n=$((_base + 7)) ;;
	esac
	if [ -z "$_n" ] && [ "$_base" = "$3" ]; then
		case $_name in
		default) _n=$(($3 + 9)) ;;
		colour[0-9] | colour[0-9][0-9] | colour[0-9][0-9][0-9] | \
			color[0-9] | color[0-9][0-9] | color[0-9][0-9][0-9])
			_n="$(($3 + 8));5;${_name#colo*r}"
			;;
		\#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])
			_hex=${_name#\#}
			_n="$(($3 + 8));2;$((16#${_hex:0:2}));$((16#${_hex:2:2}));$((16#${_hex:4:2}))"
			;;
		esac
	fi
	printf -v "$1" '%s' "$_n"
}

# style_sgr <var> <style>: escape sequence for a tmux style such as
# "fg=magenta,bold" or "fg=#bd93f9 italics". Parts it does not understand
# are ignored; an empty or "default" style gives the plain reset.
style_sgr() {
	local _part _code _params=0
	for _part in ${2//,/ }; do
		_code=
		case $_part in
		fg=*) colour_sgr _code "${_part#fg=}" 30 ;;
		bg=*) colour_sgr _code "${_part#bg=}" 40 ;;
		bold | bright) _code=1 ;;
		dim) _code=2 ;;
		italics) _code=3 ;;
		underscore) _code=4 ;;
		blink) _code=5 ;;
		reverse) _code=7 ;;
		strikethrough) _code=9 ;;
		esac
		[ -z "$_code" ] || _params="$_params;$_code"
	done
	printf -v "$1" '\033[%sm' "$_params"
}
