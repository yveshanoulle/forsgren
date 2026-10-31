package page

import (
	"regexp"
	"strconv"
	"strings"
	"testing"
)

// The TBD columns that can be turned off (forsgren#482, step 3, decisions
// #480 A and #481 B): HideTbdTimeToMain drops the Time to main per commit
// group, HideTbdPRLeadTime the PR Lead Time group and HideTbdBotPRLeadTime the
// Bot PR Lead Time group, in both figure modes, with their cells, state cells,
// share of the service row's Per repository run, notes and columns spanned.

// hiding is one switch: its group's title, its place among the five groups
// that precede the deploy group, and how it turns the group off in the data.
type hiding struct {
	name, title string
	place       int
	hide        func(*Data)
}

var hidings = []hiding{
	{"time to main", "Time to main per commit", 2, func(d *Data) { d.HideTbdTimeToMain = true }},
	{"pr lead time", "PR Lead Time", 3, func(d *Data) { d.HideTbdPRLeadTime = true }},
	{"bot pr lead time", "Bot PR Lead Time", 4, func(d *Data) { d.HideTbdBotPRLeadTime = true }},
}

// widthOf is how many columns a group has in the figures.
func widthOf(all bool) int {
	if all {
		return 3
	}
	return 1
}

// cellRe matches one cell of a row, notes included.
var cellRe = regexp.MustCompile(`(?s)<td.*?</td>`)

// cellsOf are the cells of the row of project in html.
func cellsOf(t *testing.T, html, project string) []string {
	t.Helper()
	_, rest, found := strings.Cut(html, `<th scope="row">`+project+`</th>`)
	if !found {
		t.Fatalf("want the row of %s, got none", project)
	}
	row, _, _ := strings.Cut(rest, "</tr>")
	return cellRe.FindAllString(row, -1)
}

// TestHiddenGroupsLeaveTheirCellsOut: a data row loses exactly the cells of the
// group, in both figure modes, and nothing else changes.
func TestHiddenGroupsLeaveTheirCellsOut(t *testing.T) {
	for _, all := range []bool{false, true} {
		w := widthOf(all)
		full := cellsOf(t, rendered(t, "tbd.html", inFigures(tbdData(), all)), "Acme Shop")
		for _, h := range hidings {
			data := inFigures(tbdData(), all)
			h.hide(&data)
			got := cellsOf(t, rendered(t, "tbd.html", data), "Acme Shop")
			want := append(append([]string{}, full[:h.place*w]...), full[(h.place+1)*w:]...)
			if strings.Join(got, "") != strings.Join(want, "") {
				t.Errorf("%s, all %v: want the cells without the group, got\n%q\nwant\n%q", h.name, all, got, want)
			}
		}
	}
}

// TestHiddenGroupsLeaveTheirHeadersOut: the group's header is gone in both
// figure modes, the others stay, and the header spans the columns the rows
// have, which TbdColumnsAfterProject says.
func TestHiddenGroupsLeaveTheirHeadersOut(t *testing.T) {
	for _, all := range []bool{false, true} {
		for _, h := range hidings {
			data := inFigures(tbdData(), all)
			h.hide(&data)
			got := rendered(t, "tbd.html", data)
			head, _, _ := strings.Cut(got, "</thead>")
			wantNone(t, h.name, head, ">"+h.title+"<")
			wantAll(t, h.name, head, ">Mainline Lead Time<", ">Time to deploy per commit<")
			want := 17 - 1
			if all {
				want = 33 - 3
			}
			if data.TbdColumnsAfterProject() != want || len(cellsOf(t, got, "Acme Shop")) != want {
				t.Errorf("%s, all %v: want %d columns after the project, got %d and %d cells", h.name, all, want,
					data.TbdColumnsAfterProject(), len(cellsOf(t, got, "Acme Shop")))
			}
		}
	}
}

// TestAllThreeHiddenShrinkTheNoDataSentence: a project without data spans the
// columns that are left.
func TestAllThreeHiddenShrinkTheNoDataSentence(t *testing.T) {
	for all, columns := range map[bool]int{false: 14, true: 24} {
		data := withoutData(all)
		data.HideTbdTimeToMain, data.HideTbdPRLeadTime, data.HideTbdBotPRLeadTime = true, true, true
		wantAll(t, "no data", rendered(t, "tbd.html", data), noDataRow(columns, 30))
		if data.TbdColumnsAfterProject() != columns {
			t.Errorf("all %v: want %d columns, got %d", all, columns, data.TbdColumnsAfterProject())
		}
	}
}

// TestHiddenGroupsLeaveTheirStateCellsOut: a push state is written under Mainline
// Interval (forsgren#588), Mainline Lead Time, Time to main, Commits per push and the shares, so hiding
// Time to main leaves four; the pull request states are written under PR Lead Time and Bot PR Lead Time.
func TestHiddenGroupsLeaveTheirStateCellsOut(t *testing.T) {
	const pushes, pulls = "Push activity not readable", "Pull requests not readable"
	for _, all := range []bool{false, true} {
		data := inFigures(tbdData(), all)
		data.HideTbdTimeToMain = true
		wantCount(t, rendered(t, "tbd.html", data), pushes, 4)
		data = inFigures(notReadable(), all)
		wantCount(t, rendered(t, "tbd.html", data), pulls, 4)
		data.HideTbdPRLeadTime = true
		wantCount(t, rendered(t, "tbd.html", data), pulls, 2)
		data.HideTbdBotPRLeadTime = true
		wantCount(t, rendered(t, "tbd.html", data), pulls, 0)
	}
}

// wantCount fails t unless html holds text count times.
func wantCount(t *testing.T, html, text string, count int) {
	t.Helper()
	if got := strings.Count(html, text); got != count {
		t.Errorf("want %q %d times, got %d", text, count, got)
	}
}

// perRepositorySpan is the width the first Per repository cell spans in html.
func perRepositorySpan(t *testing.T, html string) string {
	t.Helper()
	m := regexp.MustCompile(`colspan="(\d+)">Per repository`).FindStringSubmatch(html)
	if m == nil {
		t.Fatal("want a Per repository cell, got none")
	}
	return m[1]
}

// TestHiddenGroupsShrinkTheServiceRowsRun: a service row writes Per repository
// once across the five groups it has no figures for; each hidden group takes its
// columns out of that run.
func TestHiddenGroupsShrinkTheServiceRowsRun(t *testing.T) {
	for _, all := range []bool{false, true} {
		w := widthOf(all)
		data := inFigures(subRowsData(), all)
		if got := perRepositorySpan(t, rendered(t, "tbd.html", data)); got != strconv.Itoa(5*w) {
			t.Errorf("all %v: want a run of %d, got %s", all, 5*w, got)
		}
		data.HideTbdTimeToMain, data.HideTbdBotPRLeadTime = true, true
		if got := perRepositorySpan(t, rendered(t, "tbd.html", data)); got != strconv.Itoa(3*w) {
			t.Errorf("all %v: want a run of %d, got %s", all, 3*w, got)
		}
	}
}

// TestHiddenGroupsLeaveTheirNotesOut: a note that no shown cell carries is not
// listed, and the counts are those of the shown cells: Acme Tools' cut and
// created-time pull requests are counted for the people and for the bots.
func TestHiddenGroupsLeaveTheirNotesOut(t *testing.T) {
	data := tbdData()
	got := rendered(t, "tbd.html", data)
	wantAll(t, "all shown", got, "Acme Tools 2</li>", "Acme Tools 1, Acme Web 1</li>")
	data.HideTbdPRLeadTime = true
	got = rendered(t, "tbd.html", data)
	wantAll(t, "people hidden", got, "pull request was cut: Acme Tools 1</li>",
		"created time: Acme Tools 1</li>")
	wantNone(t, "people hidden", got, "Acme Web 1</li>")
	data.HideTbdBotPRLeadTime = true
	wantNone(t, "both hidden", rendered(t, "tbd.html", data), `id="tbd-note-3"`, `id="tbd-note-4"`)
	data = tbdData()
	data.HideTbdBotPRLeadTime = true
	wantAll(t, "bots hidden", rendered(t, "tbd.html", data), "pull request was cut: Acme Tools 1</li>")
}

// TestTbdPageWithTheColumnsOffGolden: the page with all three columns off and
// all the figures.
func TestTbdPageWithTheColumnsOffGolden(t *testing.T) {
	data := inFigures(tbdData(), true)
	data.HideTbdTimeToMain, data.HideTbdPRLeadTime, data.HideTbdBotPRLeadTime = true, true, true
	checkPageGolden(t, "tbd.html", "testdata/tbd.hidden.golden.html", data)
}

// TestLegendSaysATurnedOffColumnIsNotShown: the legend says in one sentence that
// a column turned off in the settings is not shown, with its notes.
func TestLegendSaysATurnedOffColumnIsNotShown(t *testing.T) {
	wantAll(t, "legend.html", rendered(t, "legend.html", calculated()),
		"A column that the settings turn off is not shown, and neither are the notes of its cells.")
}
