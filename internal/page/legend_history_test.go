package page

import (
	"strings"
	"testing"
)

// TestLegendExplainsTheHistoryPage (forsgren#68): the legend has a History
// page section that says what the periods are, that every period is banded as
// 180 days at the configured working day with the period's own count, what a
// cell, the chart and a dash mean, the limits of old periods, and how to hide
// the page; the Issues pages paragraph names the default of history_page.
func TestLegendExplainsTheHistoryPage(t *testing.T) {
	cases := map[string]struct {
		hours int
		want  []string
	}{
		"default working day": {0, []string{"at a working day of 8 hours", "on demand from 1441"}},
		"6 hours":             {6, []string{"at a working day of 6 hours", "on demand from 1081"}},
	}
	for name, tc := range cases {
		data := calculated()
		data.WorkingHours = tc.hours
		_, section, found := strings.Cut(rendered(t, "legend.html", data), "<h2>History page (beta)</h2>")
		if !found {
			t.Fatalf("%s: want a History page section in the legend", name)
		}
		section, _, _ = strings.Cut(section, "<h2>")
		for _, want := range append(tc.want, legendHistoryText...) {
			if !strings.Contains(section, want) {
				t.Errorf("%s: want %q in the History page section", name, want)
			}
		}
	}
	const shown = "history_page: unlisted"
	if !strings.Contains(rendered(t, "legend.html", calculated()), shown) {
		t.Error("want the Issues pages paragraph to list history_page among the page switches")
	}
}

// legendHistoryText are the sentences of the History page section that do not
// depend on the working day.
var legendHistoryText = []string{
	"calendar half-years (January to June, July to December, UTC)",
	"Last 6 months, the newest column, which runs up to the render time",
	"Every period is banded as 180 days",
	"the period's own count, not rescaled to 180",
	"at most 3%",
	"number · score",
	"0 to 10, 10 at the top",
	"a gap in the line, never a zero",
	"A dash means no data",
	"raise history_days, up to 1825",
	"The lead time of older periods can be a dash",
	"lost its label long ago",
	"covers only the dora_days window",
	"The Trend column is shown from two periods on",
	"a line under the heading gives the first deployment and the day the first half-year appears",
	"The History page is unlisted by default (history_page: unlisted): it is " +
		"generated and can be opened at history.html, but it has no menu entry and search" +
		" engines are asked to skip it. Set history_page: true to put it in the menu, or " +
		"history_page: false to not generate it.",
}
