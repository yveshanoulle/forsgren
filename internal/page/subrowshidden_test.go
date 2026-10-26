package page

import (
	"strings"
	"testing"
)

// sub_rows: false (forsgren#482, step 4, decision #488 A): the label and service
// rows are not shown on any table; the total rows, the numbers and the config's
// label and services keys are as before.

// tableViews are the pages that show the DORA table, one per view.
var tableViews = []string{"index.html", "standard/index.html", "numbers/index.html", "scoring/index.html",
	"numbers-scoring/index.html"}

// labelledData is the DORA table's data with Acme Shop's labels, sub rows
// hidden or not.
func labelledData(hide bool) Data {
	data := calculated()
	data.Rows = Table(labelledRows())
	data.HideSubRows = hide
	return data
}

// TestHiddenSubRowsLeaveTheDoraTableWithTheTotals: on every view the label rows
// are gone and the totals stay, headed by the project's name alone.
func TestHiddenSubRowsLeaveTheDoraTableWithTheTotals(t *testing.T) {
	for _, name := range tableViews {
		shown := rendered(t, name, labelledData(false))
		wantAll(t, name, shown, "Website</th>", "(total)", `class="label"`)
		got := rendered(t, name, labelledData(true))
		wantNone(t, name, got, "ADMIN", "Website", "IOS", "(total)", `class="label"`, `>API<`)
		wantAll(t, name, got, `<th scope="row">Acme Shop</th>`, `<th scope="row">Acme Tools</th>`,
			`<th scope="row">Acme Docs</th>`)
		if strings.Count(got, "<tr") != strings.Count(shown, "<tr")-4 {
			t.Errorf("%s: want the four label rows gone and nothing else", name)
		}
	}
}

// TestHiddenSubRowsLeaveTheHistoryPageWithTheTotals: each project's block keeps
// its total's rows and its chart; the label's measure rows go.
func TestHiddenSubRowsLeaveTheHistoryPageWithTheTotals(t *testing.T) {
	data := historyData()
	shown := rendered(t, "history.html", data)
	data.HideSubRows = true
	got := rendered(t, "history.html", data)
	wantAll(t, "shown", shown, "API: ")
	wantNone(t, "hidden", got, "API")
	wantCount(t, got, "<tbody>", 2)
	wantCount(t, got, "<svg", strings.Count(shown, "<svg"))
	wantCount(t, got, `<th scope="row">Overall Performance</th>`, 2)
	wantNone(t, "hidden", got, "(total)")
}

// TestHiddenSubRowsLeaveTheTbdPageWithTheTotals: the total rows only, and the
// notes only a label row carried are gone.
func TestHiddenSubRowsLeaveTheTbdPageWithTheTotals(t *testing.T) {
	for _, all := range []bool{false, true} {
		data := inFigures(subRowsData(), all)
		data.HideSubRows = true
		got := rendered(t, "tbd.html", data)
		wantNone(t, "tbd.html", got, `class="label"`, "API", "IOS", "Website", "Per repository", "Acme Shop: ")
		wantAll(t, "tbd.html", got, `<th scope="row">Acme Shop</th>`)
		wantCount(t, got, "<tr", 1+tbdHeaderRows(all))
	}
}

// tbdHeaderRows is how many header rows the TBD table has.
func tbdHeaderRows(all bool) int {
	if all {
		return 2
	}
	return 1
}

// TestHiddenSubRowsGoldens: one golden for each kind of page with the sub rows
// off.
func TestHiddenSubRowsGoldens(t *testing.T) {
	checkGolden(t, "testdata/index.no-sub-rows.golden.html", labelledData(true))
	history := historyData()
	history.HideSubRows = true
	checkPageGolden(t, "history.html", "testdata/history.no-sub-rows.golden.html", history)
	tbd := subRowsData()
	tbd.HideSubRows = true
	checkPageGolden(t, "tbd.html", "testdata/tbd.no-sub-rows.golden.html", tbd)
}

// TestLegendSaysSubRowsAreShownUnlessTurnedOff: one sentence in the DORA part
// and one in the TBD part.
func TestLegendSaysSubRowsAreShownUnlessTurnedOff(t *testing.T) {
	got := rendered(t, "legend.html", calculated())
	wantCount(t, got, "The rows under a project's total are shown unless the settings turn them off.", 1)
	wantCount(t, got, "The rows under a total are shown unless the settings turn them off.", 1)
}
