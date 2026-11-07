# Layout arithmetic for the menu and the popup: pure, no tmux calls.

# paginate <total> <max_rows> <page>: split <total> menu rows into pages
# that fit in <max_rows>, keeping 3 rows for page navigation when there is
# more than one page. Sets PER_PAGE, PAGES, PAGE (clamped to PAGES), and
# START and END, the range of rows on that page.
paginate() {
	if [ "$1" -le "$2" ]; then
		PER_PAGE=$1
	else
		PER_PAGE=$(($2 - 3))
		[ "$PER_PAGE" -ge 1 ] || PER_PAGE=1
	fi
	PAGES=$((($1 + PER_PAGE - 1) / PER_PAGE))
	PAGE=$3
	[ "$PAGE" -le "$PAGES" ] || PAGE=$PAGES
	START=$(((PAGE - 1) * PER_PAGE))
	END=$((START + PER_PAGE))
	[ "$END" -le "$1" ] || END=$1
}

# grid_layout <total> <cell> <gap> <width> <max_rows>: arrange <total> cells,
# each <cell> wide and <gap> apart, column by column in at most <width>
# columns and <max_rows> rows. Sets COLS, ROWS and SHOWN, the cells that fit.
# If SHOWN < <total>, the cell after them is left for a "N more" count.
grid_layout() {
	COLS=$((($4 + $3) / ($2 + $3)))
	[ "$COLS" -ge 1 ] || COLS=1
	ROWS=$((($1 + COLS - 1) / COLS))
	if [ "$ROWS" -gt "$5" ]; then
		# Too many to fit: fill the grid and use the last cell for a count.
		ROWS=$5
		SHOWN=$((ROWS * COLS - 1))
	else
		# Rebalance so the last column is not nearly empty.
		COLS=$((($1 + ROWS - 1) / ROWS))
		SHOWN=$1
	fi
}

# scroll_top <var> <selected> <top> <visible>: the first row to show of a
# list scrolled to <top>, moved as little as possible so that row
# <selected> is one of the <visible> rows shown.
scroll_top() {
	local _top=$3
	[ "$2" -ge "$_top" ] || _top=$2
	[ "$2" -lt $((_top + $4)) ] || _top=$(($2 - $4 + 1))
	[ "$_top" -ge 0 ] || _top=0
	printf -v "$1" '%d' "$_top"
}
