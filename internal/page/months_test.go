package page

import (
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// TestMonthsPageHoldsDayWeekAndMonthRows (forsgren#123, step 4): the months
// page, months.html, is the table forsgren 0.6.4 put on the issues page: the
// rows of Data.IssueRows under the header "Period", labelled by their kind,
// with the note that explains the periods. It holds no 30-day IssueDays row.
func TestMonthsPageHoldsDayWeekAndMonthRows(t *testing.T) {
	data := calculated()
	row := func(kind string, date time.Time) metrics.IssueRow {
		return metrics.IssueRow{Kind: kind, IssueDay: metrics.IssueDay{Date: date, New: 1, Total: 1, Active: true}}
	}
	data.IssueRows = []metrics.IssueRow{
		row(metrics.KindDay, october(13)),
		row(metrics.KindWeek, october(5)),
		row(metrics.KindWeek, on2026(time.September, 28)),
		row(metrics.KindMonth, on2026(time.September, 1)),
	}
	data.IssueDays = []metrics.IssueDay{{Date: october(11), New: 9, Total: 9, Active: true}}
	got := rendered(t, "months.html", data)
	wantAll(t, "months.html", got, "<title>Months · forsgren</title>", "<h1>Months</h1>", `<th scope="col">Period</th>`,
		"2026-10-13", "Week 41", "Week 40", "September 2026",
		"Days are in UTC, weeks run Monday to Sunday, months follow the calendar, "+
			"and a week that spans two months is in both.")
	wantNone(t, "months.html", got, "2026-10-11", `<th scope="col">Date</th>`, "<p>No issues were opened")
}

// TestMonthsPageSkipsInactiveRows (forsgren#89, step 16; forsgren#123, step 5):
// as for days (forsgren#108), a week or a month that is not Active has no row
// on the months page, the ones around it do. The calculation keeps them; only
// the page hides them.
func TestMonthsPageSkipsInactiveRows(t *testing.T) {
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
	got := rendered(t, "months.html", data)
	wantAll(t, "months.html", got, "Week 41", "August 2026")
	wantNone(t, "months.html", got, "2026-10-12", "Week 40", "September 2026")
}

// TestMonthsPageWithNoActiveRowShowsAMessage (forsgren#108, step 7, rule 4;
// forsgren#89, step 15; forsgren#123, step 6): when no row of any kind, day,
// week or month, is Active, the months page says so in one line and has no
// table, not even its head. The rows reach back months, so the line names no
// period: it says that nothing happened before today.
func TestMonthsPageWithNoActiveRowShowsAMessage(t *testing.T) {
	data := calculated()
	row := func(kind string, date time.Time) metrics.IssueRow {
		return metrics.IssueRow{Kind: kind, IssueDay: metrics.IssueDay{Date: date, Total: 5}}
	}
	data.IssueRows = []metrics.IssueRow{
		row(metrics.KindDay, october(13)),
		row(metrics.KindWeek, october(5)),
		row(metrics.KindMonth, on2026(time.September, 1)),
	}
	got := rendered(t, "months.html", data)
	wantAll(t, "months.html", got, "<p>No issues were opened, closed or reopened before today.</p>")
	wantNone(t, "months.html", got, "<table>", "2026-10-13", "Week 41", "September 2026")
}

// TestMonthsPageSwitchMarksOnlyMonths (forsgren#123, step 7): the view switch
// ends with issues and then months. The months page marks months current and
// links issues, the issues page marks issues and links months, and a table
// page, at the root or one folder down, links both after the views.
func TestMonthsPageSwitchMarksOnlyMonths(t *testing.T) {
	const views = `<span class="views">View: <a href="standard/">standard</a> · <a href="numbers/">numbers</a> · ` +
		`<a href="scoring/">scoring</a> · `
	data := calculated()
	data.View = viewNumbers
	wantAll(t, "months.html", rendered(t, "months.html", data), views+
		`<a href="issues.html">issues</a> · <span aria-current="page">months</span></span>`)
	wantAll(t, "issues.html", rendered(t, "issues.html", data), views+
		`<span aria-current="page">issues</span> · <a href="months.html">months</a></span>`)
	data = viewData()
	data.View = viewNumbers
	wantAll(t, "index.html", rendered(t, "index.html", data),
		`<a href="issues.html">issues</a> · <a href="months.html">months</a></span>`)
	for _, view := range []string{viewStandard, viewNumbers, viewScoring} {
		page := view + "/index.html"
		wantAll(t, page, rendered(t, page, data),
			`<a href="../issues.html">issues</a> · <a href="../months.html">months</a></span>`)
	}
}

// TestMonthsPageMatchesGolden (forsgren#123, step 8): the months page is the
// page months.html, a table of the days of the current week, the weeks and the
// months, newest first, one row of each kind here, under the header Period.
func TestMonthsPageMatchesGolden(t *testing.T) {
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
	}
	checkPageGolden(t, "months.html", "testdata/months.golden.html", data)
}

// TestMonthsPageWithoutRowsMatchesGolden (forsgren#123, step 8): the page of a
// site with no issue events yet, which Scripts/test_build_site.sh renders, has
// no Active row, so it shows the no-activity message and no table.
func TestMonthsPageWithoutRowsMatchesGolden(t *testing.T) {
	checkPageGolden(t, "months.html", "testdata/months.no-rows.golden.html", calculated())
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
	wantAll(t, "months.html", rendered(t, "months.html", data), `<th scope="row">2025</th>`)
}
