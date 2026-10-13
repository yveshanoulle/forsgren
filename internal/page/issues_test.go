package page

import (
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
		return metrics.IssueRow{Kind: kind, IssueDay: metrics.IssueDay{Date: date, New: 1, Total: 5, Active: active}}
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
		return metrics.IssueRow{Kind: kind, IssueDay: metrics.IssueDay{Date: date, Total: 5}}
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
	const views = `<span class="views">View: <a href="standard/">Standard</a> · <a href="numbers/">Numbers</a> · ` +
		`<a href="scoring/">Scoring</a> · `
	data := calculated()
	data.View = viewNumbers
	wantAll(t, "issues.html", rendered(t, "issues.html", data), views+
		`<span aria-current="page">Issues</span> · <a href="days.html">Daily</a></span>`)
	wantAll(t, "days.html", rendered(t, "days.html", data), views+
		`<a href="issues.html">Issues</a> · <span aria-current="page">Daily</span></span>`)
}

// TestIssuesPageMatchesGolden (forsgren#123, step 8; forsgren#128): the issues page is the
// page issues.html, a table of the days of the current week, the weeks and the
// months and the years, newest first, one row of each kind here, under the
// header Period (forsgren#125, step 8: the caption and the note name years).
func TestIssuesPageMatchesGolden(t *testing.T) {
	data := calculated()
	data.IssueRows = []metrics.IssueRow{
		{Kind: metrics.KindDay, IssueDay: metrics.IssueDay{
			Date: october(2), New: 3, Completed: 1, NotPlanned: 2, Duplicate: 1, Total: 7, Active: true,
		}},
		{Kind: metrics.KindWeek, IssueDay: metrics.IssueDay{
			Date: on2026(time.September, 28),
			New:  2, Completed: 4, Duplicate: 3, Other: 5, Total: 6, Active: true,
		}},
		{Kind: metrics.KindMonth, IssueDay: metrics.IssueDay{
			Date: on2026(time.August, 1), New: 1, Total: 5, Active: true,
		}},
		{Kind: metrics.KindYear, IssueDay: metrics.IssueDay{
			Date: on2026(time.January, 1).AddDate(-1, 0, 0),
			New:  6, Completed: 3, NotPlanned: 1, Duplicate: 1, Total: 4, Active: true,
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
		IssueDay: metrics.IssueDay{Date: on2026(time.January, 1).AddDate(-1, 0, 0), New: 1, Total: 1, Active: true},
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
		return metrics.IssueRow{Kind: kind, IssueDay: metrics.IssueDay{Date: date, New: 1, Total: 1, Active: true}}
	}
	data.IssueRows = []metrics.IssueRow{
		row(metrics.KindDay, october(13)),
		row(metrics.KindWeek, october(5)),
		row(metrics.KindMonth, on2026(time.September, 1)),
		row(metrics.KindYear, on2026(time.January, 1).AddDate(-1, 0, 0)),
	}
	data.IssueDays = []metrics.IssueDay{{Date: october(11), New: 9, Total: 9, Active: true}}
	got := rendered(t, "issues.html", data)
	wantAll(t, "issues.html", got, "<title>Issues · forsgren</title>", "<h1>Issues</h1>", `<th scope="col">Period</th>`,
		"2026-10-13", "Week 41", "September 2026", `<th scope="row">2025</th>`,
		"Days are in UTC, weeks run Monday to Sunday, months and years follow the calendar, "+
			"and a week that spans two months is in both.")
	wantNone(t, "issues.html", got, "2026-10-11", `<th scope="col">Date</th>`)
}

// TestIssuesPageWithoutRowsMatchesGolden (forsgren#128, step 5): the issues page
// of a site with no issue events yet has no Active row, so it shows the
// no-activity message and no table.
func TestIssuesPageWithoutRowsMatchesGolden(t *testing.T) {
	checkPageGolden(t, "issues.html", "testdata/issues.no-rows.golden.html", calculated())
}
