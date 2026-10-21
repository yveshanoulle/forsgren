package page

import "testing"

// TestTbdPageGolden (forsgren#253, step 2 of 7): the TBD page is a root page,
// tbd.html, with its heading and, until its metrics come, a line that says the
// page is coming and shows no number.
func TestTbdPageGolden(t *testing.T) {
	checkPageGolden(t, "tbd.html", "testdata/tbd.golden.html", viewData())
}

// TestTbdPageHasItsHeadingAndSaysItIsComing (forsgren#253): the title and the
// h1 (id tbd-heading) name trunk-based development, and the body says the page
// is coming, with no table and no number.
func TestTbdPageHasItsHeadingAndSaysItIsComing(t *testing.T) {
	got := rendered(t, "tbd.html", viewData())
	wantAll(t, "tbd.html", got, "<title>Trunk-based development (TBD) · ",
		`<h1 id="tbd-heading">Trunk-based development (TBD)</h1>`, "metrics are coming to this page")
	wantNone(t, "tbd.html", got, "<table", "<svg")
}

// TestTbdPageIsAfterHistoryInTheRootPages (forsgren#253): the page is one of
// the root pages, labelled TBD, after the History page.
func TestTbdPageIsAfterHistoryInTheRootPages(t *testing.T) {
	last := rootPages[len(rootPages)-1]
	if last.Name != TbdPage || last.Label != "TBD" {
		t.Errorf("want the last root page %q labelled TBD, got %+v", TbdPage, last)
	}
}
