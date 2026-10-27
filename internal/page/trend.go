package page

// The arrow that says which way a count of open issues moved (forsgren#126,
// forsgren#114): up, down or unchanged from the period before. Red and green
// mean a rising and a falling count, not worse and better; the colours are
// styles.css's, hung on the class, and the meaning is also in words.

import (
	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// trendView is what the "trend" template shows: the class the colours hang on,
// the arrow, how much the count moved (Change, always zero or more) with Sign
// (1 up, -1 down, 0 unchanged), which the template writes as the plus or minus
// sign itself, and the label a screen reader reads.
type trendView struct {
	Class, Arrow, Label string
	Sign                int
	Change              string
}

// trendViewOf is the view of a count called what ("open issues") that moved
// the way t says, by change (negative for Down): the template function "trend".
func trendViewOf(what string, t metrics.Trend, change int) trendView {
	switch t {
	case metrics.TrendUp:
		moved := metrics.GroupDigits(change)
		return trendView{"trend-up", "▲", what + " increased by " + moved, 1, moved}
	case metrics.TrendDown:
		moved := metrics.GroupDigits(-change)
		return trendView{"trend-down", "▼", what + " decreased by " + moved, -1, moved}
	}
	return trendView{"trend-flat", "–", what + " unchanged", 0, "0"}
}

// bugTrendViewOf is the view of the open bugs: trendViewOf's, except that a
// count that did not change hangs on the blue class (forsgren#152), the template
// function "bugtrend".
func bugTrendViewOf(t metrics.Trend, change int) trendView {
	view := trendViewOf("open bugs", t, change)
	if view.Sign == 0 {
		view.Class = "trend-flat-bugs"
	}
	return view
}
