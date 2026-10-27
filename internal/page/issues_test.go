package page

import (
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// TestIssuesPageSkipsInactiveRows (forsgren#89, step 16; forsgren#123, step 5):
// as for days (forsgren#108), a week or a month that is not Active has no row
// on the issues page, the ones around it do. The calculation keeps them; only
// the page hides them.
func TestIssuesPageSkipsInactiveRows(t *testing.T) {
	data := calculated()
	row := func(kind string, date time.Time, active bool) metrics.IssueRow {
		return metrics.IssueRow{Kind: kind, IssueDay: metrics.IssueDay{Date: date, New: 1, Open: 5, Active: active}}
	}
	data.IssueRows = []metrics.IssueRow{
		row(metrics.KindDay, october(12), false),
		row(metrics.KindWeek, october(5), true),
		row(metrics.KindWeek, on2026(time.September, 28), false),
		row(metrics.KindMonth, on2026(time.September, 1), false),
		row(metrics.KindMonth, on2026(time.August, 1), true),
	}
	got := rendered(t, "issues.html", data)
	wantAll(t, "issues.html", got, "Week 41", "August 2026")
	wantNone(t, "issues.html", got, "2026-10-12", "Week 40", "September 2026")
}

// TestIssuesPageWithNoActiveRowShowsAMessage (forsgren#108, step 7, rule 4;
// forsgren#89, step 15; forsgren#123, step 6): when no row of any kind, day,
// week or month, is Active, the issues page says so in one line and has no
// table, not even its head. The rows reach back months, so the line names no
// period: it says that nothing happened before today.
func TestIssuesPageWithNoActiveRowShowsAMessage(t *testing.T) {
	data := calculated()
	row := func(kind string, date time.Time) metrics.IssueRow {
		return metrics.IssueRow{Kind: kind, IssueDay: metrics.IssueDay{Date: date, Open: 5}}
	}
	data.IssueRows = []metrics.IssueRow{
		row(metrics.KindDay, october(13)),
		row(metrics.KindWeek, october(5)),
		row(metrics.KindMonth, on2026(time.September, 1)),
	}
	got := rendered(t, "issues.html", data)
	wantAll(t, "issues.html", got, "<p>No issues were opened, closed or reopened before today.</p>")
	wantNone(t, "issues.html", got, "<table>", "2026-10-13", "Week 41", "September 2026")
}

// TestIssuesAndDaysPagesMarkOnlyThemselves (forsgren#123, step 7; forsgren#128,
// step 6): the menu ends with issues and then Daily. The issues page marks
// issues current and links Daily, the days page marks Daily and links issues.
func TestIssuesAndDaysPagesMarkOnlyThemselves(t *testing.T) {
	data := calculated()
	data.View = viewNumbers
	wantAll(t, "issues.html", rendered(t, "issues.html", data), wantMenu("", "Issues", "page"))
	wantAll(t, "days.html", rendered(t, "days.html", data), wantMenu("", "Daily", "page"))
}

// TestIssuesPageMatchesGolden (forsgren#123, step 8; forsgren#128): the issues page is the
// page issues.html, a table of the days of the current week, the weeks and the
// months and the years, newest first, one row of each kind here, under the
// header Period (forsgren#125, step 8: the note names years; forsgren#128: no
// caption).
func TestIssuesPageMatchesGolden(t *testing.T) {
	data := calculated()
	data.IssueRows = []metrics.IssueRow{
		{Kind: metrics.KindDay, IssueDay: metrics.IssueDay{
			Date: october(2), New: 3, Completed: 1, NotPlanned: 2, Duplicate: 1, Open: 7, Total: 10, Active: true,
		}},
		{Kind: metrics.KindWeek, IssueDay: metrics.IssueDay{
			Date: on2026(time.September, 28),
			New:  2, Completed: 4, Duplicate: 3, Other: 5, Open: 6, Total: 8, Active: true,
		}},
		{Kind: metrics.KindMonth, IssueDay: metrics.IssueDay{
			Date: on2026(time.August, 1), New: 1, Open: 5, Total: 5, Active: true,
		}},
		{Kind: metrics.KindYear, IssueDay: metrics.IssueDay{
			Date: on2026(time.January, 1).AddDate(-1, 0, 0),
			New:  6, Completed: 3, NotPlanned: 1, Duplicate: 1, Open: 4, Total: 9, Active: true,
		}},
	}
	checkPageGolden(t, "issues.html", "testdata/issues.golden.html", data)
}

// TestIssueRowLabelOfAYearIsTheBareYear (forsgren#125, step 7): a year row is
// labelled by its year alone, "2025", not by its first day, and the page shows
// that label in its row.
func TestIssueRowLabelOfAYearIsTheBareYear(t *testing.T) {
	data := calculated()
	data.IssueRows = []metrics.IssueRow{{
		Kind:     metrics.KindYear,
		IssueDay: metrics.IssueDay{Date: on2026(time.January, 1).AddDate(-1, 0, 0), New: 1, Open: 1, Active: true},
	}}
	rows := data.IssueTableRows()
	if len(rows) != 1 || rows[0].Label != "2025" {
		t.Errorf("want the label 2025, got %v", rows)
	}
	wantAll(t, "issues.html", rendered(t, "issues.html", data), `<th scope="row">2025</th>`)
}

// TestIssuesPageHoldsDayWeekMonthAndYearRows (forsgren#128, step 4): the issues
// page, issues.html, is what months.html was: the rows of Data.IssueRows under
// the header Period, named Issues, and none of the 30-day IssueDays rows.
func TestIssuesPageHoldsDayWeekMonthAndYearRows(t *testing.T) {
	data := calculated()
	row := func(kind string, date time.Time) metrics.IssueRow {
		return metrics.IssueRow{Kind: kind, IssueDay: metrics.IssueDay{Date: date, New: 1, Open: 1, Active: true}}
	}
	data.IssueRows = []metrics.IssueRow{
		row(metrics.KindDay, october(13)),
		row(metrics.KindWeek, october(5)),
		row(metrics.KindMonth, on2026(time.September, 1)),
		row(metrics.KindYear, on2026(time.January, 1).AddDate(-1, 0, 0)),
	}
	data.IssueDays = []metrics.IssueDay{{Date: october(11), New: 9, Open: 9, Active: true}}
	got := rendered(t, "issues.html", data)
	wantAll(t, "issues.html", got, "<title>Issues · forsgren</title>", `<h1 id="issues-heading">Issues</h1>`,
		`<th scope="col">Period</th>`, "2026-10-13", "Week 41", "September 2026", `<th scope="row">2025</th>`)
	wantNone(t, "issues.html", got, "2026-10-11", `<th scope="col">Date</th>`)
}

// TestIssuesPageWithoutRowsMatchesGolden (forsgren#128, step 5): the issues page
// of a site with no issue events yet has no Active row, so it shows the
// no-activity message and no table.
func TestIssuesPageWithoutRowsMatchesGolden(t *testing.T) {
	checkPageGolden(t, "issues.html", "testdata/issues.no-rows.golden.html", calculated())
}

// TestIssueTablesHaveNoCaption (forsgren#128, step 9; decision #133): the
// tables of the issues and days pages have no caption; the page's heading
// names each table and its scrolling region.
func TestIssueTablesHaveNoCaption(t *testing.T) {
	data := calculated()
	data.IssueDays = []metrics.IssueDay{{Date: october(2), New: 1, Open: 1, Active: true}}
	data.IssueRows = []metrics.IssueRow{{Kind: metrics.KindMonth, IssueDay: metrics.IssueDay{
		Date: on2026(time.September, 1), New: 1, Open: 1, Active: true,
	}}}
	for name, heading := range map[string]string{"issues.html": "Issues", "days.html": "Daily"} {
		id := strings.TrimSuffix(name, ".html") + "-heading"
		got := rendered(t, name, data)
		wantAll(t, name, got, `<h1 id="`+id+`">`+heading+`</h1>`,
			`role="region" aria-labelledby="`+id+`"`, `<table aria-labelledby="`+id+`" class="no-wrap">`)
		wantNone(t, name, got, "<caption")
	}
}

// periodsNote explains the periods of the issues pages (forsgren#125).
const periodsNote = "Days are in UTC, weeks run Monday to Sunday, months and years follow the calendar, " +
	"and a week that spans two months is in both."

// TestPeriodsNoteIsInTheLegend (forsgren#128, step 12; decision #133): the
// note on the periods moves from under the issues table to the legend, in its
// own section, Issues pages.
func TestPeriodsNoteIsInTheLegend(t *testing.T) {
	data := calculated()
	data.IssueRows = []metrics.IssueRow{{Kind: metrics.KindDay, IssueDay: metrics.IssueDay{
		Date: october(2), New: 1, Open: 1, Active: true,
	}}}
	wantAll(t, "legend.html", rendered(t, "legend.html", data),
		"<h2>Issues pages</h2>\n    <p>"+periodsNote+"</p>\n")
	wantNone(t, "issues.html", rendered(t, "issues.html", data), "Days are in UTC")
}

// openBugsDay is a day with 5 open issues, 2 of them bugs, and 9 created.
var openBugsDay = metrics.IssueDay{Date: october(2), New: 1, Open: 5, OpenBugs: 2, Total: 9, Active: true}

// issuesPageOf is issues.html rendered with days as day rows, newest first.
func issuesPageOf(t *testing.T, days ...metrics.IssueDay) string {
	t.Helper()
	data := calculated()
	for _, d := range days {
		data.IssueRows = append(data.IssueRows, metrics.IssueRow{Kind: metrics.KindDay, IssueDay: d})
	}
	return rendered(t, "issues.html", data)
}

// TestIssuesTableHeadsTheOpenIssuesColumnOpen (forsgren#134, step 1): the
// column that counts the issues open at the end of each period is headed
// Open, not Total, which the next steps give to the issues ever created.
func TestIssuesTableHeadsTheOpenIssuesColumnOpen(t *testing.T) {
	got := issuesPageOf(t, metrics.IssueDay{Date: october(2), New: 1, Open: 5, Active: true})
	wantAll(t, "issues.html", got, `<th scope="col" class="num">Other</th>
            <th scope="col" class="num">Open</th>`)
}

// TestIssuesTableShowsTheIssuesCreatedInATotalColumnAfterOpenBugs (forsgren#134,
// step 3; forsgren#126): after Open and Open bugs, a column headed Total shows
// the issues created up to the end of the period, open or closed, from
// IssueDay.Total.
func TestIssuesTableShowsTheIssuesCreatedInATotalColumnAfterOpenBugs(t *testing.T) {
	got := issuesPageOf(t, openBugsDay)
	wantAll(t, "issues.html", got, `<th scope="col" class="num">Open bugs</th>
            <th scope="col" class="num">Total</th>`, `open bugs unchanged">–</span></td>
            <td class="num">9</td>`)
}

// TestIssuesTableShowsTheOpenBugsInAColumnRightAfterOpen (forsgren#126): the
// column headed Open bugs comes right after Open and shows IssueDay.OpenBugs.
func TestIssuesTableShowsTheOpenBugsInAColumnRightAfterOpen(t *testing.T) {
	wantAll(t, "issues.html", issuesPageOf(t, openBugsDay), `<th scope="col" class="num">Open</th>
            <th scope="col" class="num">Open bugs</th>`, `–</span></td>
            <td class="num">2 <span class="trend-flat-bugs" role="img" aria-label="open bugs unchanged">–</span></td>`)
}

// TestIssuesTableShowsOpenOutOfTotalInAColumnNextToTotal (forsgren#134, step
// 6): the last column, headed Open / Total, shows IssueDay.OpenShare: 5 open of
// 9 created is 55%, and a row that created none shows the dash.
func TestIssuesTableShowsOpenOutOfTotalInAColumnNextToTotal(t *testing.T) {
	data := calculated()
	data.IssueRows = []metrics.IssueRow{
		{Kind: metrics.KindDay, IssueDay: metrics.IssueDay{Date: october(2), New: 1, Open: 5, Total: 9, Active: true}},
		{Kind: metrics.KindDay, IssueDay: metrics.IssueDay{Date: october(1), Completed: 1, Active: true}},
	}
	wantAll(t, "issues.html", rendered(t, "issues.html", data), `<th scope="col" class="num">Total</th>
            <th scope="col" class="num">Open / Total</th>`, `<td class="num">9</td>
            <td class="num">55%</td>`, `<td class="num">0</td>
            <td class="num">—</td>`)
}

// columnsNote explains the last three columns of the issues tables
// (forsgren#134).
const columnsNote = "Open is the issues open at the end of the period. Total is the issues created up to the end " +
	"of the period, open or closed; a reopened issue is not created again. Open / Total is Open out of Total, " +
	"in whole percent, rounded down, and a dash when Total is 0."

// TestLegendExplainsTheOpenTotalAndOpenOutOfTotalColumns (forsgren#134, step
// 7): the legend's Issues pages section, after the note on the periods, says
// what Open, Total and Open / Total count, and how the percent is cut.
func TestLegendExplainsTheOpenTotalAndOpenOutOfTotalColumns(t *testing.T) {
	wantAll(t, "legend.html", rendered(t, "legend.html", calculated()),
		"<p>"+periodsNote+"</p>\n    <p>"+columnsNote+"</p>\n")
}

// TestIssuesTableShowsAnArrowForTheDirectionOfTheOpenColumn (forsgren#126,
// forsgren#114): after the Open count of each row, a span with role img and an
// aria-label in words says which way it moved from the period before, with the
// class the colours hang on: an arrow up and the change when it rose, an arrow
// down and the change when it fell, a dash when it did not change.
func TestIssuesTableShowsAnArrowForTheDirectionOfTheOpenColumn(t *testing.T) {
	wantArrows(t, "open issues", "trend-flat", func(day metrics.IssueDay, count, change int) metrics.IssueDay {
		day.Open, day.OpenChange = count, change
		return day
	})
}

// TestIssuesTableShowsAnArrowForTheDirectionOfTheOpenBugsColumn (forsgren#126):
// after the open bugs of each row the same arrow as after Open, from
// OpenBugsTrend and OpenBugsChange, its label naming open bugs.
func TestIssuesTableShowsAnArrowForTheDirectionOfTheOpenBugsColumn(t *testing.T) {
	wantArrows(t, "open bugs", "trend-flat-bugs", func(day metrics.IssueDay, count, change int) metrics.IssueDay {
		day.OpenBugs, day.OpenBugsChange = count, change
		return day
	})
}

// wantArrows renders three days whose count of what ("open issues" or "open
// bugs"), set by set, is 5 up by 3, 2 down by 2 and 4 unchanged, and fails
// unless each count has its arrow, class (flat for the unchanged one, blue for
// open bugs, forsgren#152) and aria-label in words.
func wantArrows(t *testing.T, what, flat string, set func(day metrics.IssueDay, count, change int) metrics.IssueDay) {
	t.Helper()
	got := issuesPageOf(t,
		set(metrics.IssueDay{Date: october(3), Active: true}, 5, 3),
		set(metrics.IssueDay{Date: october(2), Active: true}, 2, -2),
		set(metrics.IssueDay{Date: october(1), Active: true}, 4, 0))
	span := func(count int, class, change, symbol string) string {
		return fmt.Sprintf(`<td class="num">%d <span class="%s" role="img" aria-label="%s %s">%s</span></td>`,
			count, class, what, change, symbol)
	}
	wantAll(t, "issues.html", got,
		span(5, "trend-up", "increased by 3", "▲ +3"),
		span(2, "trend-down", "decreased by 2", "▼ −2"),
		span(4, flat, "unchanged", "–"))
}

// trendNote explains the arrows after Open and Open bugs (forsgren#126).
const trendNote = "An arrow after Open and after Open bugs shows which way the count moved from the end of " +
	"the period before: red when it rose, green when it fell, and grey when it did not change (blue after " +
	"Open bugs, where a count of 0 open bugs is green too). Red and green mean rose and fell, not worse and better. " +
	"A day is compared with the day before, a week with the week before, a month with the month before " +
	"and a year with the year before; " +
	"the oldest row of each kind is compared with the count just before its period, even when that period " +
	"is outside the rows shown."

// bugsNote explains the Open bugs column (forsgren#126).
const bugsNote = "Open bugs is Open counted over the issues that carry the GitHub label bug, as the label is at " +
	"the latest collection, so adding or removing the label moves the issue's whole history."

// TestLegendExplainsTheTrendArrows (forsgren#126, forsgren#114): the legend's
// Issues pages section says what the red, green and grey arrows mean, that red
// and green are not worse and better, and what the oldest row of each kind is
// compared with.
func TestLegendExplainsTheTrendArrows(t *testing.T) {
	wantAll(t, "legend.html", rendered(t, "legend.html", calculated()), "<p>"+trendNote+"</p>\n")
}

// TestLegendExplainsTheOpenBugsColumn (forsgren#126): the legend says what
// Open bugs counts and that the label is the one at the latest collection.
func TestLegendExplainsTheOpenBugsColumn(t *testing.T) {
	wantAll(t, "legend.html", rendered(t, "legend.html", calculated()), "<p>"+bugsNote+"</p>\n")
}

// TestAZeroInTheOpenBugsCellIsGreenWhateverTheArrow (forsgren#151): a count of
// 0 open bugs hangs on class bugs-zero, which styles.css gives the green of
// the falling arrow, after a fall and unchanged alike (the dash stays blue); a
// count above 0 and the incomplete cell carry no such class. The Open column's
// 0 is not coloured.
func TestAZeroInTheOpenBugsCellIsGreenWhateverTheArrow(t *testing.T) {
	zeroAfterFall := metrics.IssueDay{Date: october(4), Open: 0, OpenBugs: 0, OpenBugsChange: -1, Active: true}
	zeroUnchanged := metrics.IssueDay{Date: october(3), Active: true}
	three := metrics.IssueDay{Date: october(2), Open: 3, OpenBugs: 3, OpenBugsChange: -1, Active: true}
	incomplete := metrics.IssueDay{Date: october(1), BugsIncomplete: true, Active: true}
	got := issuesPageOf(t, zeroAfterFall, zeroUnchanged, three, incomplete)
	zero := func(arrow string) string {
		return `<td class="num"><span class="bugs-zero">0</span> <span class="` + arrow + `</span></td>`
	}
	wantAll(t, "issues.html", got,
		zero(`trend-down" role="img" aria-label="open bugs decreased by 1">▼ −1`),
		zero(`trend-flat-bugs" role="img" aria-label="open bugs unchanged">–`),
		`<td class="num">3 <span class="trend-down"`)
	if n := strings.Count(got, `class="bugs-zero"`); n != 2 {
		t.Errorf("want class bugs-zero on exactly the two zero open bugs counts, got %d in:\n%s", n, got)
	}
}

// TestNoWrapTablesAreTheIssuesNumbersAndScoringTables (forsgren#153, step 7;
// decision #160 point 4): the tables whose cells are a date, a number or a
// number with its trend carry class no-wrap, so none of their cells breaks
// onto a second line. The standard view's band text and the settings table
// have long cells and still wrap.
func TestNoWrapTablesAreTheIssuesNumbersAndScoringTables(t *testing.T) {
	data := acmeTable()
	data.IssueDays = []metrics.IssueDay{{Date: october(2), New: 1, Open: 1, Active: true}}
	data.IssueRows = []metrics.IssueRow{{Kind: metrics.KindMonth, IssueDay: metrics.IssueDay{
		Date: on2026(time.September, 1), New: 1, Open: 1, Active: true,
	}}}
	const marked = `class="no-wrap"`
	for _, name := range []string{"issues.html", "days.html", "numbers/index.html", "scoring/index.html"} {
		if got := rendered(t, name, data); !strings.Contains(got, marked) {
			t.Errorf("want the table of %s to carry %s, got:\n%s", name, marked, got)
		}
	}
	for _, name := range []string{"standard/index.html", "index.html", "settings.html"} {
		wantNone(t, name, rendered(t, name, data), marked)
	}
}

// bugsIncompleteCell is the Open bugs cell of a row whose bug count cannot be
// trusted (forsgren#140, decision #171): a dash and a word instead of a number
// and an arrow, explained to the eye by title and to a screen reader by label.
const bugsIncompleteCell = `<td class="num"><span role="img" ` +
	`aria-label="Open bugs incomplete: a repository's bug list was too long to read in full" ` +
	`title="A repository's bug list was too long to read in full, so the number of open bugs is not shown">` +
	`— (incomplete)</span></td>`

// TestAnIncompleteOpenBugsCellShowsADashAndNoArrow (forsgren#140): a row with
// BugsIncomplete shows bugsIncompleteCell instead of the number and the arrow,
// on the issues page and on the days page; a row without it keeps both.
func TestAnIncompleteOpenBugsCellShowsADashAndNoArrow(t *testing.T) {
	incomplete := openBugsDay
	incomplete.BugsIncomplete, incomplete.OpenBugsChange = true, 3
	got := issuesPageOf(t, incomplete)
	wantAll(t, "issues.html", got, bugsIncompleteCell)
	wantNone(t, "issues.html", got, "open bugs increased", "open bugs unchanged", `<td class="num">2 `)
	data := calculated()
	data.IssueDays = []metrics.IssueDay{incomplete}
	wantAll(t, "days.html", rendered(t, "days.html", data), bugsIncompleteCell)
	wantNone(t, "issues.html", issuesPageOf(t, openBugsDay), "incomplete")
}

// TestIssuesPageWithAnIncompleteOpenBugsCellMatchesGolden (forsgren#140).
func TestIssuesPageWithAnIncompleteOpenBugsCellMatchesGolden(t *testing.T) {
	day := openBugsDay
	day.BugsIncomplete = true
	data := calculated()
	data.IssueRows = []metrics.IssueRow{{Kind: metrics.KindDay, IssueDay: day}}
	checkPageGolden(t, "issues.html", "testdata/issues.incomplete.golden.html", data)
}

// incompleteNote explains the incomplete Open bugs cell (forsgren#140).
const incompleteNote = "When the bug list of a repository is too long to read in full (the read stops at 10,000 " +
	"issues), Open bugs shows — (incomplete) instead of a number in every row, because a partial count would " +
	"look complete. The number returns by itself after a complete read."

// TestLegendExplainsTheIncompleteOpenBugsCell (forsgren#140): the legend says,
// right after the note on Open bugs, why the cell can show — (incomplete) and
// that it clears after a complete read.
func TestLegendExplainsTheIncompleteOpenBugsCell(t *testing.T) {
	wantAll(t, "legend.html", rendered(t, "legend.html", calculated()),
		"<p>"+bugsNote+"</p>\n    <p>"+incompleteNote+"</p>\n    <p>"+trendNote+"</p>\n")
}

// closedColumnsNote and issueLimitsNote are the legend's paragraphs on what
// New, Completed, Not planned, Duplicate and Other count, and on the two limits
// of the issue history (forsgren#112).
const (
	closedColumnsNote = "New, Completed, Not planned, Duplicate and Other count what happened in the row's " +
		"period (UTC): New is the issues created; Completed, Not planned and Duplicate are the issues closed " +
		"with that reason; Other is the issues closed with no reason, or with a reason forsgren does not know, " +
		"so every close is counted in exactly one of the four. A reopen is counted in none of them; it only " +
		"puts the issue back into Open."
	issueLimitsNote = "Two limits: a reopen is dated when the collection sees it, not when it happened, so " +
		"it can fall in a later period than the real one; and when a repository has more issues than the one " +
		"full read takes (it stops at 100 pages of 100 issues), its older issues are missing and its " +
		"historical Total stays incomplete. The — (incomplete) note covers Open bugs and Bugs lead time only."
)

// TestLegendExplainsTheClosedColumnsAndTheLimitsOfTheIssueHistory
// (forsgren#112): the Issues pages section says what the New and the four
// closed columns count, in the row's period, that a reopen counts in none, and
// the two limits, the dating of a reopen and the full-read cap.
func TestLegendExplainsTheClosedColumnsAndTheLimitsOfTheIssueHistory(t *testing.T) {
	wantAll(t, "legend.html", rendered(t, "legend.html", calculated()),
		"<p>"+columnsNote+"</p>\n    <p>"+closedColumnsNote+"</p>", "<p>"+issueLimitsNote+"</p>")
}

// TestIssuesPageShowsLeadTimeAfterCompleted (forsgren#202, step 7): the issues
// and days tables head a column Lead time right after Completed, whose cell is
// IssueDay.LeadTime.Cell: 25 h is 1 d 1 h, and a row that completed no issue
// shows the dash.
func TestIssuesPageShowsLeadTimeAfterCompleted(t *testing.T) {
	data := calculated()
	lead := metrics.LeadMedian{Median: 25 * time.Hour, Count: 2}
	days := []metrics.IssueDay{
		{Date: october(2), Completed: 2, NotPlanned: 1, LeadTime: lead, Active: true},
		{Date: october(1), NotPlanned: 1, Active: true},
	}
	data.IssueDays = days
	for _, d := range days {
		data.IssueRows = append(data.IssueRows, metrics.IssueRow{Kind: metrics.KindDay, IssueDay: d})
	}
	for _, name := range []string{"issues.html", "days.html"} {
		wantAll(t, name, rendered(t, name, data), `<th scope="col" class="num">Completed</th>
            <th scope="col" class="num">Lead time</th>`, `<td class="num">2</td>
            <td class="num">1 d 1 h</td>
            <td class="num">—</td>
            <td class="num">1</td>`, `<td class="num">0</td>
            <td class="num">—</td>
            <td class="num">—</td>
            <td class="num">1</td>`)
	}
}

// The two "— (incomplete)" spans of the issues table: the Open bugs cell's and
// the Bugs lead time cell's, each naming the number it hides (forsgren#202).
const (
	openBugsIncomplete = `<span role="img" aria-label="Open bugs incomplete: a repository's bug list was too long ` +
		`to read in full" title="A repository's bug list was too long to read in full, so the number of open bugs ` +
		`is not shown">— (incomplete)</span>`
	bugsLeadTimeIncomplete = `<span role="img" aria-label="Bugs lead time incomplete: a repository's bug list was too ` +
		`long to read in full" title="A repository's bug list was too long to read in full, so the bugs lead time ` +
		`is not shown">— (incomplete)</span>`
)

// TestIssuesPageShowsBugsLeadTimeAndItsIncompleteNote (forsgren#202, step 8):
// the issues and days tables head a column Bugs lead time right after Lead
// time, whose cell is IssueDay.BugsLeadTime.Cell: 10 h for one bug, the dash
// for none. When the row is BugsIncomplete the cell is the "— (incomplete)"
// note of Open bugs, and the Lead time cell before it is still the number.
func TestIssuesPageShowsBugsLeadTimeAndItsIncompleteNote(t *testing.T) {
	lead := metrics.LeadMedian{Median: 25 * time.Hour, Count: 2}
	bugs := metrics.LeadMedian{Median: 10 * time.Hour, Count: 1}
	header := `<th scope="col" class="num">Lead time</th>
            <th scope="col" class="num">Bugs lead time</th>
            <th scope="col" class="num">Not planned</th>`
	for _, name := range []string{"issues.html", "days.html"} {
		data := calculated()
		days := []metrics.IssueDay{
			{Date: october(2), Completed: 2, NotPlanned: 1, LeadTime: lead, BugsLeadTime: bugs, Active: true},
			{Date: october(1), Completed: 1, NotPlanned: 1, LeadTime: lead, Active: true},
		}
		data.IssueDays = days
		for _, d := range days {
			data.IssueRows = append(data.IssueRows, metrics.IssueRow{Kind: metrics.KindDay, IssueDay: d})
		}
		wantAll(t, name, rendered(t, name, data), header, `<td class="num">1 d 1 h</td>
            <td class="num">10 h</td>
            <td class="num">1</td>`, `<td class="num">1 d 1 h</td>
            <td class="num">—</td>
            <td class="num">1</td>`)
		for i := range days {
			days[i].BugsIncomplete = true
		}
		data.IssueDays = days
		data.IssueRows = nil
		for _, d := range days {
			data.IssueRows = append(data.IssueRows, metrics.IssueRow{Kind: metrics.KindDay, IssueDay: d})
		}
		wantAll(t, name, rendered(t, name, data), `<td class="num">1 d 1 h</td>
            <td class="num">`+bugsLeadTimeIncomplete+`</td>`, openBugsIncomplete)
		wantNone(t, name, rendered(t, name, data), `<td class="num">1 d 1 h</td>
            <td class="num"><span role="img" aria-label="Open bugs incomplete`)
	}
}

// leadTimeNote is the legend's paragraph on the Lead time and Bugs lead time
// columns (forsgren#202).
const leadTimeNote = "Lead time is the median time from an issue's creation to its Completed close, over the " +
	"issues completed in the row's period; Not planned, Duplicate and Other closes are not counted. A reopened " +
	"issue is measured from its creation to the close in that period. Bugs lead time is the same over the " +
	"issues that carry the GitHub label bug, and shows — (incomplete) on the same rule as Open bugs. A dash " +
	"means no issue was completed in the period."

// TestLegendDescribesLeadTimeAndBugsLeadTime (forsgren#202, step 9): the Issues
// pages section describes both lead time columns in one paragraph right after
// the paragraph on the closed columns.
func TestLegendDescribesLeadTimeAndBugsLeadTime(t *testing.T) {
	wantAll(t, "legend.html", rendered(t, "legend.html", calculated()),
		"<p>"+closedColumnsNote+"</p>\n    <p>"+leadTimeNote+"</p>\n")
}
