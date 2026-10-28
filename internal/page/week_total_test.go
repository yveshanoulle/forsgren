package page

import (
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// The Total row of the Week page (forsgren#552, decision #553 A, built as a
// header line on Yves's reply): the first row of the body, right under the
// column headers, summing every project row of weekPageData, Acme Shop and
// Acme Docs (the Website and API label rows are already in Acme Shop's):
// commits {31,40,1234,8,17,6,2}, deployments {5,8,11,7,5,7,15}, failed
// {1,0,3,0,0,0,3}.

// weekTotalRowStart opens the Total row.
const weekTotalRowStart = `<tr class="week-total">`

// weekTotalRow is the Total row of the Week page rendered from data, up to its
// end, or the empty string when the page has none.
func weekTotalRow(t *testing.T, data Data) string {
	t.Helper()
	_, rest, found := strings.Cut(rendered(t, "week.html", data), weekTotalRowStart)
	if !found {
		return ""
	}
	row, _, _ := strings.Cut(rest, "</tr>")
	return row
}

// numCells are the lines of figure cells holding texts, in order.
func numCells(texts ...string) string {
	var lines strings.Builder
	for _, text := range texts {
		lines.WriteString(`            <td class="num">` + text + "</td>\n")
	}
	return lines.String()
}

// TestWeekPageStartsWithATotalRowUnderTheHeaders: the Total row, headed
// Total, is the first row of the body, before the first project row, and the
// table has no footer.
func TestWeekPageStartsWithATotalRowUnderTheHeaders(t *testing.T) {
	got := rendered(t, "week.html", weekPageData())
	wantAll(t, "week.html", got,
		"</thead>\n        <tbody>\n          "+weekTotalRowStart+"\n            <th scope=\"row\">Total</th>\n")
	wantNone(t, "week.html", got, "<tfoot")
	wantCount(t, got, weekTotalRowStart, 1)
	if strings.Index(got, weekTotalRowStart) > strings.Index(got, `<th scope="row">Acme Shop</th>`) {
		t.Error("want the Total row before the first project row")
	}
}

// TestWeekTotalRowSumsEveryProjectRow: Total holds the counts of the sums and
// the Fail rate of the sums (7 of 58 plus 7); a weekday the shares of the
// sums and its fail rate.
func TestWeekTotalRowSumsEveryProjectRow(t *testing.T) {
	row := weekTotalRow(t, weekPageData())
	wantAll(t, "week.html Total row", row,
		"<th scope=\"row\">Total</th>\n"+numCells("1"+metrics.ThousandsSpace+"338", "58", "7", "10%")+
			numCells("2.3%", "8.6%", "14%", "16%"),
		numCells("92%", "18%")+"            "+highestCell("42%")+"\n            "+highestCell("21%")+"\n",
		numCells("0.14%", "25%")+"            "+highestCell("42%")+"\n"+numCells("16%"))
	wantCount(t, row, "<td", 32)
}

// TestWeekTotalRowLeavesOutCommitsWithoutWeekCommits: three cells per group,
// no commits total.
func TestWeekTotalRowLeavesOutCommitsWithoutWeekCommits(t *testing.T) {
	data := weekPageData()
	data.WeekCommits = false
	row := weekTotalRow(t, data)
	wantAll(t, "week.html Total row", row,
		"<th scope=\"row\">Total</th>\n"+numCells("58", "7", "10%", "8.6%", "14%", "16%"))
	wantNone(t, "week.html Total row", row, "338")
	wantCount(t, row, "<td", 24)
}

// TestWeekTotalRowIsTheSameWithoutSubRows: sub_rows: false leaves the label
// rows out of the body; the Total row sums the project rows all the same.
func TestWeekTotalRowIsTheSameWithoutSubRows(t *testing.T) {
	data := weekPageData()
	data.HideSubRows = true
	if got, want := weekTotalRow(t, data), weekTotalRow(t, weekPageData()); got != want || got == "" {
		t.Errorf("want the same Total row without sub-rows, got:\n%s\nwant:\n%s", got, want)
	}
}

// TestWeekPageWithoutATableHasNoTotalRow: no projects, or nothing collected,
// is the one line and no Total row.
func TestWeekPageWithoutATableHasNoTotalRow(t *testing.T) {
	noProjects := calculated()
	noProjects.NoProjects = true
	for _, data := range []Data{noProjects, calculated()} {
		wantNone(t, "week.html", rendered(t, "week.html", data), "<tfoot", weekTotalRowStart, `<th scope="row">Total</th>`)
	}
}

// TestWeekPageWithOneProjectHasNoTotalRow (forsgren#552 step 2, Yves's
// ruling): one project, its label and service rows included, has no Total row,
// as a Total row would only repeat the project's row; with or without sub-rows.
func TestWeekPageWithOneProjectHasNoTotalRow(t *testing.T) {
	data := weekPageData()
	data.Week.Rows = data.Week.Rows[:3] // Acme Shop, its Website label and its API service
	for _, hide := range []bool{false, true} {
		data.HideSubRows = hide
		got := rendered(t, "week.html", data)
		wantNone(t, "week.html", got, "<tfoot", weekTotalRowStart, `<th scope="row">Total</th>`)
		wantAll(t, "week.html", got, `<th scope="row">Acme Shop</th>`)
	}
}

// TestWeekPageWithTwoProjectsHasATotalRow: two project rows are enough for
// the Total row, without any label row.
func TestWeekPageWithTwoProjectsHasATotalRow(t *testing.T) {
	data := weekPageData()
	data.Week.Rows = []metrics.WeekRow{data.Week.Rows[0], data.Week.Rows[3]}
	wantAll(t, "week.html", rendered(t, "week.html", data), weekTotalRowStart, `<th scope="row">Total</th>`)
}
