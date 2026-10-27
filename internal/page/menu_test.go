package page

import (
	"strings"
	"testing"
)

// menuEntry is one entry of the menu: its address from the root and its
// label.
type menuEntry struct{ href, label string }

// menuEntries are the menu's entries in its order (forsgren#128, decision
// #133): the three views, the numbers and scoring page, then the issues, days and history pages.
var menuEntries = []menuEntry{
	{"standard/", "Standard"}, {"numbers/", "Numbers"}, {"scoring/", "Scoring"},
	{"numbers-scoring/", "Numbers and scoring"},
	{"issues.html", "Issues"}, {"days.html", "Daily"}, {"history.html", "History"}, {"tbd.html", "TBD"},
	{"week.html", "Week"},
}

// wantMenu is the menu of a page whose links start with base: the label of
// current plain text, marked aria-current=mark, the others links; no entry is
// current when current is empty.
func wantMenu(base, current, mark string) string {
	parts := make([]string, len(menuEntries))
	for i, e := range menuEntries {
		parts[i] = `<a href="` + base + e.href + `">` + e.label + `</a>`
		if e.label == current {
			parts[i] = `<span aria-current="` + mark + `">` + e.label + `</span>`
		}
	}
	return `<nav class="views">View: ` + strings.Join(parts, " · ") + `</nav>`
}

// menuCase is what a page's menu marks: the current entry's label and its
// aria-current, and the base of its links.
type menuCase struct{ base, current, mark string }

// menuCases are the menus of the pages: a view's page and
// the issues and days pages mark themselves, the settings and legend pages
// nothing; root is the root's.
func menuCases(root menuCase) map[string]menuCase {
	return map[string]menuCase{
		"index.html":                 root,
		"standard/index.html":        {"../", "Standard", "page"},
		"numbers/index.html":         {"../", "Numbers", "page"},
		"scoring/index.html":         {"../", "Scoring", "page"},
		"numbers-scoring/index.html": {"../", "Numbers and scoring", "page"},
		"issues.html":                {"", "Issues", "page"},
		"days.html":                  {"", "Daily", "page"},
		"history.html":               {"", "History", "page"},
		"tbd.html":                   {"", "TBD", "page"},
		"week.html":                  {"", "Week", "page"},
		"settings.html":              {},
		"legend.html":                {},
	}
}

// TestEveryPageOpensWithTheMenu (forsgren#128, step 8; decision #133): all
// eight pages open with one menu, "View: Standard · Numbers · Scoring · Issues
// · Daily", above the page's content and nowhere else, not in a table's
// caption. A view's page and the issues and days pages mark themselves
// aria-current="page"; the root marks the view it shows aria-current="true"
// and none without one; the settings and legend pages mark none. The
// placeholder site has the menu too.
func TestEveryPageOpensWithTheMenu(t *testing.T) {
	withView := viewData()
	withView.View = viewNumbers
	cases := map[string]struct {
		data Data
		root menuCase
	}{
		"with data":   {withView, menuCase{"", "Numbers", "true"}},
		"placeholder": {calculated(), menuCase{}},
	}
	for name, c := range cases {
		pages := menuCases(c.root)
		for _, page := range PageNames() {
			wantOneMenuFirst(t, name+" "+page, rendered(t, page, c.data), pages[page])
		}
	}
}

// TestMenuLeavesOutNumbersAndScoringWhenHidden (forsgren#55, decision #187):
// a site that hides the numbers and scoring page has no entry for it in any
// page's menu, and the other entries stay in their order.
func TestMenuLeavesOutNumbersAndScoringWhenHidden(t *testing.T) {
	data := viewData()
	data.Hidden = hideNumbersScoring()
	for page, next := range map[string]string{"index.html": `Scoring</a> · <a href="issues.html">`,
		"scoring/index.html": `Scoring</span> · <a href="../issues.html">`,
		"issues.html":        `Scoring</a> · <span aria-current="page">Issues`} {
		got := rendered(t, page, data)
		wantNone(t, page, got, "Numbers and scoring", "numbers-scoring/")
		wantAll(t, page, got, next)
	}
}

// TestMenuPutsNumbersAndScoringBetweenScoringAndIssues (forsgren#55, decision
// #187): the entry follows Scoring and precedes Issues, a link from the root
// and from every folder, plain text with aria-current="page" on its own page,
// and never the root's marked view, whatever the root shows.
func TestMenuPutsNumbersAndScoringBetweenScoringAndIssues(t *testing.T) {
	data := viewData()
	data.View = viewScoring
	root := rendered(t, "index.html", data)
	wantAll(t, "index.html", root, `<span aria-current="true">Scoring</span> · `+
		`<a href="numbers-scoring/">Numbers and scoring</a> · <a href="issues.html">Issues</a>`)
	own := rendered(t, "numbers-scoring/index.html", data)
	wantAll(t, "numbers-scoring/index.html", own, `<a href="../scoring/">Scoring</a> · `+
		`<span aria-current="page">Numbers and scoring</span> · <a href="../issues.html">Issues</a>`)
	wantNone(t, "index.html", root, `<span aria-current="true">Numbers and scoring`,
		`<span aria-current="page">Numbers and scoring`)
}

// wantOneMenuFirst fails unless the page got opens with the menu m and holds
// no other.
func wantOneMenuFirst(t *testing.T, name, got string, m menuCase) {
	t.Helper()
	want := "<body>\n  " + wantMenu(m.base, m.current, m.mark) + "\n  <main>\n"
	if !strings.Contains(got, want) {
		t.Errorf("%s: want the page to open with\n%s\ngot:\n%s", name, want, got)
	}
	if n := strings.Count(got, "View: "); n != 1 {
		t.Errorf("%s: want one menu on the page, got %d", name, n)
	}
}

// TestNoPageLinksBackToTheTable (forsgren#128, step 10): the menu on every
// page reaches the table, so no page has a "Back to the table" link, with
// data or without.
func TestNoPageLinksBackToTheTable(t *testing.T) {
	wantOnNoPage(t, viewData(), "Back to the table")
	wantOnNoPage(t, calculated(), "Back to the table")
}

// TestEveryPageEndsWithTheSameFooter (forsgren#128, step 11; decision #133):
// every page, with data or without, ends with one footer: the version line
// with Calculated at, then Settings and Legend, linked through ../ one folder
// down.
func TestEveryPageEndsWithTheSameFooter(t *testing.T) {
	for name, data := range map[string]Data{"with data": viewData(), "placeholder": calculated()} {
		for _, page := range PageNames() {
			base := menuCases(menuCase{})[page].base
			want := " Calculated at 2026-10-03 12:00 UTC</p>\n    <p><a href=\"" + base + "settings.html\">Settings</a> " +
				"<a href=\"" + base + "legend.html\">Legend</a></p>\n  </footer>\n"
			wantAll(t, name+" "+page, rendered(t, page, data), want)
		}
	}
}

// TestLegendPageIsTitledLegend (forsgren#39, step 4; forsgren#128, step 13;
// Yves's ruling on decision #133): the legend page's title is its heading,
// Legend, as its footer link reads, then the site's title; "What the bands
// mean" is gone from it, and its header shows no site-name line (forsgren#41).
func TestLegendPageIsTitledLegend(t *testing.T) {
	got := rendered(t, "legend.html", viewData())
	wantAll(t, "legend.html", got, "<title>Legend · forsgren</title>", "<h1>Legend</h1>")
	wantNone(t, "legend.html", got, "What the bands mean", `class="site-name"`)
}

// TestMenuEndsWithHistoryAndOmitsItWhenHidden (forsgren#68, #253): the entry is
// after Daily and before TBD, a link from the root and from every folder, plain text
// with aria-current="page" on its own page; a site that hides the history
// page has no entry for it in any page's menu, and the others stay.
func TestMenuEndsWithHistoryAndOmitsItWhenHidden(t *testing.T) {
	data := viewData()
	for page, want := range map[string]string{
		"index.html": `<a href="days.html">Daily</a> · <a href="history.html">History</a> · ` +
			`<a href="tbd.html">TBD</a> · <a href="week.html">Week</a></nav>`,
		"scoring/index.html": `<a href="../days.html">Daily</a> · <a href="../history.html">History</a> · ` +
			`<a href="../tbd.html">TBD</a> · <a href="../week.html">Week</a></nav>`,
		"history.html": `<a href="days.html">Daily</a> · <span aria-current="page">History</span> · ` +
			`<a href="tbd.html">TBD</a> · <a href="week.html">Week</a></nav>`,
	} {
		wantAll(t, page, rendered(t, page, data), want)
	}
	data.Hidden = map[string]bool{HistoryPage: true}
	for _, page := range []string{"index.html", "scoring/index.html", "days.html"} {
		got := rendered(t, page, data)
		wantNone(t, page, got, "History", "history.html")
		wantAll(t, page, got, "Daily")
	}
}
