package page

import (
	"strings"
	"testing"
)

// TestLegendExplainsTheReportPeriod (forsgren#542, decision #543 A): where
// the legend names the window it says what the footer's Report Start and
// Report End are.
func TestLegendExplainsTheReportPeriod(t *testing.T) {
	got := rendered(t, "legend.html", calculated())
	for _, want := range []string{
		"The footer of every page gives the report period: Report Start and Report End are the first and the " +
			"last minute of that window, in UTC, so Report End is the Calculated at time and Report Start is " +
			"the window's days before it.",
		"The window rolls with the render time; it is not whole calendar days.",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("want %q in the legend", want)
		}
	}
}
