package page

import (
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// on2026 is midnight UTC on day d of month m of 2026, the Date of a row of the
// days or issues page.
func on2026(m time.Month, d int) time.Time { return time.Date(2026, m, d, 0, 0, 0, 0, time.UTC) }

// october is on2026 in October.
func october(d int) time.Time { return on2026(time.October, d) }

// TestDaysPageShowsTheLastThirtyDays (forsgren#123, step 1): the days page
// is back to 0.6.3: it tabulates Data.IssueDays under the header "Date", with
// no caption (forsgren#128) and no note, and
// shows no week or month row even when Data.IssueRows holds some.
func TestDaysPageShowsTheLastThirtyDays(t *testing.T) {
	data := calculated()
	data.IssueDays = []metrics.IssueDay{
		{Date: october(13), New: 2, Open: 4, Active: true},
		{Date: october(12), Completed: 1, Open: 3, Active: true},
	}
	data.IssueRows = []metrics.IssueRow{
		{Kind: metrics.KindWeek, IssueDay: metrics.IssueDay{Date: october(5), New: 1, Open: 1, Active: true}},
		{Kind: metrics.KindMonth, IssueDay: metrics.IssueDay{
			Date: on2026(time.September, 1), New: 1, Open: 1, Active: true,
		}},
	}
	got := rendered(t, "days.html", data)
	wantAll(t, "days.html", got, "2026-10-13", "2026-10-12", `<th scope="col">Date</th>`)
	wantNone(t, "days.html", got, "Week 41", "September 2026", `<th scope="col">Period</th>`,
		"a week that spans two months")
}

// TestIssueTableRowsLabelsDayWeekAndMonthRows (forsgren#89, step 13;
// forsgren#123): the rows of Data.IssueRows are labelled by their kind: a day
// by its date, a week by the ISO number of its Monday (5 October 2026 is in
// week 41), a month by its name and year. The issues page shows them.
func TestIssueTableRowsLabelsDayWeekAndMonthRows(t *testing.T) {
	row := func(kind string, date time.Time) metrics.IssueRow {
		return metrics.IssueRow{Kind: kind, IssueDay: metrics.IssueDay{Date: date, New: 1, Open: 1, Active: true}}
	}
	data := calculated()
	data.IssueRows = []metrics.IssueRow{
		row(metrics.KindDay, october(13)),
		row(metrics.KindWeek, october(5)),
		row(metrics.KindMonth, on2026(time.September, 1)),
	}
	var got []string
	for _, r := range data.IssueTableRows() {
		got = append(got, r.Label)
	}
	if want := []string{"2026-10-13", "Week 41", "September 2026"}; !slices.Equal(got, want) {
		t.Errorf("want the labels %q, got %q", want, got)
	}
}

// TestDaysPageSkipsInactiveDays (forsgren#108, step 5): a day that is not
// Active (nothing new, closed or reopened) has no row on the days page, the
// days around it do. The calculation keeps the day (rule 3); only the page hides it.
func TestDaysPageSkipsInactiveDays(t *testing.T) {
	data := calculated()
	data.IssueDays = []metrics.IssueDay{
		{Date: october(3), New: 1, Open: 5, Active: true},
		{Date: october(2), Open: 5},
		{Date: october(1), Completed: 1, Open: 5, Active: true},
	}
	got := rendered(t, "days.html", data)
	wantAll(t, "days.html", got, "2026-10-03", "2026-10-01")
	wantNone(t, "days.html", got, "2026-10-02")
}

// TestDaysPageWithNoActiveDayShowsAMessage (forsgren#108, step 7, rule 4):
// when no day of the window is Active, the days page says so in one line
// and has no table, not even its head.
func TestDaysPageWithNoActiveDayShowsAMessage(t *testing.T) {
	data := calculated()
	data.IssueDays = []metrics.IssueDay{{Date: october(13), Open: 5}, {Date: october(12), Open: 5}}
	got := rendered(t, "days.html", data)
	wantAll(t, "days.html", got, "<p>No issues were opened, closed or reopened in the last 30 days.</p>")
	wantNone(t, "days.html", got, "<table>", "2026-10-13")
}

// TestDaysPageMenuIgnoresTheConfiguredView (forsgren#76, decision #102):
// the config's view: decides which view the root page shows, not what the
// days page marks. Whatever Data.View is, the days page's menu links all
// three views and only Daily is current.
func TestDaysPageMenuIgnoresTheConfiguredView(t *testing.T) {
	menu := wantMenu("", "Daily", "page")
	for _, view := range []string{viewStandard, viewNumbers, viewScoring} {
		t.Run(view, func(t *testing.T) {
			data := calculated()
			data.View = view
			got := rendered(t, "days.html", data)
			if !strings.Contains(got, menu) || strings.Count(got, "aria-current") != 1 {
				t.Errorf("want the menu %q with the only aria-current, got:\n%s", menu, got)
			}
		})
	}
}

// TestDaysPageMatchesGolden (forsgren#128, step 2): the page of the days is
// days.html, what issues.html showed before: a table of the last 30 days, newest
// first, titled Daily, with the menu that ends issues, Daily.
func TestDaysPageMatchesGolden(t *testing.T) {
	data := calculated()
	data.IssueDays = []metrics.IssueDay{
		{Date: october(2), New: 3, Completed: 1, NotPlanned: 2, Duplicate: 1, Open: 7, Total: 10, Active: true},
		{Date: october(1), New: 0, Completed: 0, Open: 5, Total: 8, Active: true},
		{
			Date: on2026(time.September, 30),
			New:  2, Completed: 4, Duplicate: 3, Other: 5, Open: 6, Active: true,
		},
	}
	checkPageGolden(t, "days.html", "testdata/days.golden.html", data)
}

// TestDaysPageWithoutDaysMatchesGolden (forsgren#128, step 3): the days page of a
// site with no issue events yet has no Active day, so it shows the no-activity
// message and no table.
func TestDaysPageWithoutDaysMatchesGolden(t *testing.T) {
	checkPageGolden(t, "days.html", "testdata/days.placeholder.golden.html", calculated())
}
