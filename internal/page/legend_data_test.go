package page

import (
	"strings"
	"testing"
)

// legendDataText are the sentences of the legend's Data page section
// (forsgren#579, step 4).
var legendDataText = []string{
	"The Data page shows, for each project and under it for each label, service or rule, " +
		"the first date forsgren stored data of each kind: Deployments, Commits, Pushes, " +
		"Merged pull requests, Failure issues and Issues.",
	"Each date is a day in UTC.",
	"A date marked ▲ is after Report Start: the window is only partly covered, " +
		"and the metrics of that kind count from that date on.",
	"A dash means nothing of that kind is stored.",
	"A service or rule row reads Per repository for Pushes, Merged pull requests and Issues, " +
		"as these are read per repository, not per service or rule.",
	"A project's date is the earliest over its repositories.",
	"The first stored date is when forsgren started collecting that data, " +
		"not when the repository started.",
	"Under the table, Which pages use which data names the pages each kind feeds.",
	"The Data page is in the menu by default. Set data_page: unlisted to take it out of the menu; " +
		"it is still generated, can be opened at data.html, and search engines are asked to skip it. " +
		"Set data_page: false to leave it out.",
}

// TestLegendExplainsTheDataPage: the legend has a Data page section, right
// after the Week page section and before the Settings page section, with the
// sentences of legendDataText.
func TestLegendExplainsTheDataPage(t *testing.T) {
	before, rest, found := strings.Cut(rendered(t, "legend.html", calculated()), "<h2>Data page</h2>")
	if !found {
		t.Fatal("want a Data page section in the legend")
	}
	section, after, _ := strings.Cut(rest, "<h2>")
	if !strings.Contains(before, "<h2>Week page</h2>") {
		t.Error("want the Data page section after the Week page section")
	}
	if !strings.HasPrefix(after, "Settings page</h2>") {
		t.Errorf("want the Settings page section right after, got %.40q", after)
	}
	for _, want := range legendDataText {
		if !strings.Contains(section, want) {
			t.Errorf("want %q in the Data page section", want)
		}
	}
}
