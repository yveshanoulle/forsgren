package page

import (
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/config"
)

// The Commits columns of the Week page are off unless week_commits is true
// (forsgren#548, decision #549 A): weekPageData has them on, and this file
// holds the default, where a header group is Deployments, Failed and Fail
// rate.

// weekPageDataWithoutCommits is weekPageData with Data.WeekCommits off, as a
// Data made from a config that leaves week_commits out.
func weekPageDataWithoutCommits() Data {
	data := weekPageData()
	data.WeekCommits = false
	// Failures on every row, so no run of cells repeats (the HTML duplication
	// ceiling is 0%) now that the commit cells do not break the runs.
	data.Week.Rows[1].Failed = [7]int{1, 0, 2, 0, 3, 1, 0}
	data.Week.Rows[3].Failed = [7]int{2, 0, 0, 1, 0, 0, 4}
	return data
}

func TestWeekPageWithoutCommitsMatchesGolden(t *testing.T) {
	checkPageGolden(t, "week.html", "testdata/week.no-commits.golden.html", weekPageDataWithoutCommits())
}

// TestWeekPageWithoutCommitsHasThreeColumnsPerGroup: no Commits header under
// Total or a weekday, each of the 8 groups spans 3 columns and has Deployments,
// Failed and Fail rate under it, 24 headers in all.
func TestWeekPageWithoutCommitsHasThreeColumnsPerGroup(t *testing.T) {
	got := rendered(t, "week.html", weekPageDataWithoutCommits())
	wantNone(t, "week.html", got, ">Commits<", " commits\"", `colspan="4"`)
	wantCount(t, got, `<th scope="colgroup" colspan="3">`, 8)
	wantCount(t, got, `<th scope="col" aria-label=`, 24)
	wantAll(t, "week.html", got, `<th scope="colgroup" colspan="3">Total</th>`,
		`<th scope="col" aria-label="Total deployments" class="num">Deployments</th>`,
		`<th scope="col" aria-label="Sunday failed deployments" class="num">Failed</th>`,
		`<th scope="col" aria-label="Monday fail rate" class="num">Fail rate</th>`)
}

// TestWeekPageWithoutCommitsHasThreeCellsPerGroupInEveryRow: 24 figure cells
// after the row header, none of them the en dash of a row Per repository, and
// the deployments figures unchanged.
func TestWeekPageWithoutCommitsHasThreeCellsPerGroupInEveryRow(t *testing.T) {
	got := rendered(t, "week.html", weekPageDataWithoutCommits())
	wantCount(t, got, "<td", 4*24)
	wantNone(t, "week.html", got, "<td>\u2013</td>", "1\u202f338")
	wantAll(t, "week.html", got, `<td class="num">29</td>`, `<td class="num">2.7%</td>`, `<td class="num">19%</td>`)
}

// TestWeekPageWithCommitsHasFourColumnsPerGroup: week_commits true brings the
// Commits columns back, 32 headers and 32 cells per row.
func TestWeekPageWithCommitsHasFourColumnsPerGroup(t *testing.T) {
	got := rendered(t, "week.html", weekPageData())
	wantCount(t, got, `<th scope="col" aria-label=`, 32)
	wantCount(t, got, "<td", 4*32)
	if first, _, _ := strings.Cut(got, "Fail rate"); !strings.Contains(first, ">Commits<") {
		t.Error("want Commits as the first header of the Total group")
	}
}

// TestWeekPageWithoutCommitsStillMarksTheHighest: the highest marks do not
// depend on the Commits columns.
func TestWeekPageWithoutCommitsStillMarksTheHighest(t *testing.T) {
	got := rendered(t, "week.html", weekPageDataWithoutCommits())
	wantCount(t, got, `class="num highest"`, 9)
}

// TestSettingsPageListsWeekCommitsOffByDefault: the row shows false (not
// set), the values true and false, and the default false.
func TestSettingsPageListsWeekCommitsOffByDefault(t *testing.T) {
	data := Placeholder("1.0.0")
	data.Settings = (config.Config{}).Settings()
	wantAll(t, "settings.html", rendered(t, "settings.html", data), `<th scope="row">week_commits</th>
            <td>false (not set)</td>
            <td>true, false</td>
            <td>false</td>`)
}
