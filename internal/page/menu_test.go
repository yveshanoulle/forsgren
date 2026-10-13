package page

import (
	"strings"
	"testing"
)

// menuEntry is one entry of the menu: its address from the root and its
// label.
type menuEntry struct{ href, label string }

// menuEntries are the menu's entries in its order (forsgren#128, decision
// #133): the three views, then the issues page and the days page.
var menuEntries = []menuEntry{
	{"standard/", "Standard"}, {"numbers/", "Numbers"}, {"scoring/", "Scoring"},
	{"issues.html", "Issues"}, {"days.html", "Daily"},
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
		"index.html":          root,
		"standard/index.html": {"../", "Standard", "page"},
		"numbers/index.html":  {"../", "Numbers", "page"},
		"scoring/index.html":  {"../", "Scoring", "page"},
		"issues.html":         {"", "Issues", "page"},
		"days.html":           {"", "Daily", "page"},
		"settings.html":       {},
		"legend.html":         {},
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
