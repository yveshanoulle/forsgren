package page

import (
	"strings"
	"testing"
)

// legendTbdText are the sentences of the legend's TBD page section
// (forsgren#253): the cell format, what is counted and how, what a dash is,
// what comes later and the default of tbd_page.
var legendTbdText = []string{
	"the Mainline Interval of each project",
	"written mean ± deviation (gaps), for example 2 h ± 1 h (3)",
	"the sample standard deviation",
	"the commits that deployments of the last 30 days shipped",
	"each commit once",
	"by their author date",
	"A dash means fewer than two commits",
	"With one gap the mean is shown, and the deviation is a dash",
	"between deployed commits, not every commit of the mainline",
	"Next to them the cell gives the median and the 90th percentile (p90) of the gaps, written median 5 min · p90 1 h",
	"The median is the middle gap, or the mean of the two middle gaps when there is an even number of them",
	"p90 is the nearest-rank percentile: the gap at position 0.9 × the number of gaps, rounded up, of the gaps " +
		"sorted from the shortest, so nine tenths of the gaps are no longer than it",
	"The median needs two gaps and p90 needs ten gaps",
	"With fewer than ten gaps p90 would only be the longest gap",
	"A mean far above the median, and a deviation far above the mean, point at a few long gaps among short ones",
	"The two metrics are read together",
	"The Mainline Interval shows how often the commits that were deployed were made, by author date, in the window",
	"It will show how long a commit takes from its creation to reaching the main branch",
	"A short interval with a long lead time points at long-lived branches",
	"Mainline Lead Time is not on this page yet",
	"The TBD page is unlisted by default (tbd_page: unlisted): it is " +
		"generated and can be opened at tbd.html, but it has no menu entry and search" +
		" engines are asked to skip it. Set tbd_page: true to put it in the menu, or " +
		"tbd_page: false to not generate it.",
}

// TestLegendExplainsTheTbdPage (forsgren#253): the legend has a TBD page
// section after the History page's, whose sentences name the window in force;
// the Issues pages paragraph lists tbd_page among the page keys and its
// default.
func TestLegendExplainsTheTbdPage(t *testing.T) {
	got := rendered(t, "legend.html", calculated())
	_, section, found := strings.Cut(got, "<h2>Trunk-based development [TBD] (BETA)</h2>")
	if !found {
		t.Fatal("want a TBD page section in the legend")
	}
	section, _, _ = strings.Cut(section, "<h2>")
	for _, want := range legendTbdText {
		if !strings.Contains(section, want) {
			t.Errorf("want %q in the TBD page section", want)
		}
	}
	data := calculated()
	data.DoraDays = 90
	if !strings.Contains(rendered(t, "legend.html", data), "deployments of the last 90 days shipped") {
		t.Error("want the TBD section to name the window in force")
	}
	tbdHeading, historyHeading := "<h2>Trunk-based development [TBD] (BETA)</h2>", "<h2>History page (BETA)</h2>"
	if strings.Index(got, tbdHeading) < strings.Index(got, historyHeading) {
		t.Error("want the TBD page section after the History page section")
	}
}

// TestLegendSaysEachTbdSentenceOnce (forsgren#271): the explanation of the
// Mainline Interval and the Mainline Lead Time line are in the legend once,
// and the TBD page does not repeat them.
func TestLegendSaysEachTbdSentenceOnce(t *testing.T) {
	got := rendered(t, "legend.html", calculated())
	for _, once := range []string{"Mainline Lead Time is not on this page yet", "each commit once",
		"A dash means fewer than two commits", "sample standard deviation of the time between commits",
		"deployments of the last 30 days shipped"} {
		if n := strings.Count(got, once); n != 1 {
			t.Errorf("want %q once in the legend, got %d", once, n)
		}
	}
}
