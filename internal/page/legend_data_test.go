package page

import (
	"strings"
	"testing"
)

// legendDataText are the sentences of the legend's Data page section
// (forsgren#579, step 4; forsgren#582).
var legendDataText = []string{
	"The Data page shows, for each project and under it for each label, service or rule, " +
		"the first date forsgren stored data of each kind: Issues, Commits, Pushes, " +
		"Deployments and Merged pull requests.",
	"Each date is a day in UTC.",
	"A date marked ▲ is after Report Start: the window is only partly covered, " +
		"and the metrics of that kind count from that date on.",
	"A dash means nothing of that kind is stored.",
	"A date marked … is only where the read of a repository's pushes stopped at its page limit: " +
		"earlier data is not yet read, so it does not mean the repository started on that date. " +
		"It marks Pushes, and Commits when the pushed commits give its date.",
	"Commits is the oldest author date over the deployed commits and the pushed commits; " +
		"a service or rule row has its own deployed commits only.",
	"A service or rule row reads Per repository for Issues, Pushes and Merged pull requests, " +
		"as these are read per repository, not per service or rule.",
	"A project's date is the earliest over its repositories.",
	"The first stored date is when forsgren started collecting that data, " +
		"not when the repository started.",
	"Under the table, Which pages use which data names the pages each kind feeds.",
	"The Data page is linked in the footer, next to Settings, Legend and Dictionary, by default. " +
		"Set data_page: unlisted to take the link away; the page is still generated, can be opened at data.html, " +
		"and search engines are asked to skip it. Set data_page: false to leave it out.",
}

// dataSection is the legend's Data page section, and what comes right
// before and after it.
func dataSection(t *testing.T) (before, section, after string) {
	t.Helper()
	before, rest, found := strings.Cut(rendered(t, "legend.html", calculated()), "<h2>Data page</h2>")
	if !found {
		t.Fatal("want a Data page section in the legend")
	}
	section, after, _ = strings.Cut(rest, "<h2>")
	return before, section, after
}

// TestLegendExplainsTheDataPage: the legend has a Data page section, right
// after the Week page section and before the Settings page section, with the
// sentences of legendDataText.
func TestLegendExplainsTheDataPage(t *testing.T) {
	before, section, after := dataSection(t)
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

// TestLegendDataSectionSaysNoMenuOrFailureIssues (forsgren#582): the page has
// no Failure issues column and no menu entry any more.
func TestLegendDataSectionSaysNoMenuOrFailureIssues(t *testing.T) {
	_, section, _ := dataSection(t)
	for _, stale := range []string{"Failure issues", "in the menu"} {
		if strings.Contains(section, stale) {
			t.Errorf("want no %q in the Data page section", stale)
		}
	}
}
