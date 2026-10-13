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
		row(metrics.KindWeek, time.Date(2026, time.September, 28, 0, 0, 0, 0, time.UTC)),
		row(metrics.KindMonth, time.Date(2026, time.September, 1, 0, 0, 0, 0, time.UTC)),
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
	month := func(m time.Month) time.Time { return time.Date(2026, m, 1, 0, 0, 0, 0, time.UTC) }
	data.IssueRows = []metrics.IssueRow{
		row(metrics.KindDay, october(12), false),
		row(metrics.KindWeek, october(5), true),
		row(metrics.KindWeek, time.Date(2026, time.September, 28, 0, 0, 0, 0, time.UTC), false),
		row(metrics.KindMonth, month(time.September), false),
		row(metrics.KindMonth, month(time.August), true),
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
		row(metrics.KindMonth, time.Date(2026, time.September, 1, 0, 0, 0, 0, time.UTC)),
	}
	got := rendered(t, "months.html", data)
	wantAll(t, "months.html", got, "<p>No issues were opened, closed or reopened before today.</p>")
	wantNone(t, "months.html", got, "<table>", "2026-10-13", "Week 41", "September 2026")
}
