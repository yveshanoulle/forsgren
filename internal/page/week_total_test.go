package page

import (
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// The Total row of the Week page (forsgren#552, decision #553 A): a footer
// row summing every project row of weekPageData, Acme Shop and Acme Docs (the
// Website and API label rows are already in Acme Shop's): commits
// {31,40,1234,8,17,6,2}, deployments {5,8,11,7,5,7,15}, failed {1,0,3,0,0,0,3}.

// weekFooter is the table footer of the Week page rendered from data, or the
// empty string when the page has none.
func weekFooter(t *testing.T, data Data) string {
	t.Helper()
	_, rest, found := strings.Cut(rendered(t, "week.html", data), "<tfoot>")
	if !found {
		return ""
	}
	footer, _, _ := strings.Cut(rest, "</tfoot>")
	return footer
}

// numCells are the lines of figure cells holding texts, in order.
func numCells(texts ...string) string {
	var lines strings.Builder
	for _, text := range texts {
		lines.WriteString(`            <td class="num">` + text + "</td>\n")
	}
	return lines.String()
}

// TestWeekPageEndsWithATotalRowInTheFooter: the footer is one row headed
// Total, after the body.
func TestWeekPageEndsWithATotalRowInTheFooter(t *testing.T) {
	got := rendered(t, "week.html", weekPageData())
	wantAll(t, "week.html", got, "</tbody>\n        <tfoot>\n          <tr>\n            <th scope=\"row\">Total</th>\n",
		"</tr>\n        </tfoot>\n      </table>")
	wantCount(t, weekFooter(t, weekPageData()), "<tr", 1)
}

// TestWeekTotalRowSumsEveryProjectRow: Total holds the counts of the sums and
// the Fail rate of the sums (7 of 58 plus 7); a weekday the shares of the
// sums and its fail rate.
func TestWeekTotalRowSumsEveryProjectRow(t *testing.T) {
	footer := weekFooter(t, weekPageData())
	wantAll(t, "week.html footer", footer,
		"<th scope=\"row\">Total</th>\n"+numCells("1"+metrics.ThousandsSpace+"338", "58", "7", "10%")+
			numCells("2.3%", "8.6%", "14%", "16%"),
		numCells("92%", "18%")+"            "+highestCell("42%")+"\n            "+highestCell("21%")+"\n",
		numCells("0.14%", "25%")+"            "+highestCell("42%")+"\n"+numCells("16%"))
	wantCount(t, footer, "<td", 32)
}

// TestWeekTotalRowLeavesOutCommitsWithoutWeekCommits: three cells per group,
// no commits total.
func TestWeekTotalRowLeavesOutCommitsWithoutWeekCommits(t *testing.T) {
	data := weekPageData()
	data.WeekCommits = false
	footer := weekFooter(t, data)
	wantAll(t, "week.html footer", footer,
		"<th scope=\"row\">Total</th>\n"+numCells("58", "7", "10%", "8.6%", "14%", "16%"))
	wantNone(t, "week.html footer", footer, "338")
	wantCount(t, footer, "<td", 24)
}

// TestWeekTotalRowIsTheSameWithoutSubRows: sub_rows: false leaves the label
// rows out of the body; the Total row sums the project rows all the same.
func TestWeekTotalRowIsTheSameWithoutSubRows(t *testing.T) {
	data := weekPageData()
	data.HideSubRows = true
	if got, want := weekFooter(t, data), weekFooter(t, weekPageData()); got != want || got == "" {
		t.Errorf("want the same Total row without sub-rows, got:\n%s\nwant:\n%s", got, want)
	}
}

// TestWeekPageWithoutATableHasNoTotalRow: no projects, or nothing collected,
// is the one line and no footer.
func TestWeekPageWithoutATableHasNoTotalRow(t *testing.T) {
	noProjects := calculated()
	noProjects.NoProjects = true
	for _, data := range []Data{noProjects, calculated()} {
		wantNone(t, "week.html", rendered(t, "week.html", data), "<tfoot", `<th scope="row">Total</th>`)
	}
}
