package metrics

import (
	"slices"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// TestIssueMonthsCountsEachCompleteCalendarMonth (forsgren#89, step 1): with
// now on 14 October and 2 months, the rows are September and August, newest
// first, dated the first of the month. 23:59:59 on 31 August and the next
// 00:00:00 land in different rows, both repositories count, a close counts in
// the column of its reason, and nothing in the current month counts.
func TestIssueMonthsCountsEachCompleteCalendarMonth(t *testing.T) {
	at := func(month time.Month, d, h, m, s int) time.Time {
		return time.Date(2026, month, d, h, m, s, 0, time.UTC)
	}
	events := []history.IssueEvent{
		issueEvent("acme/app", "created", at(time.August, 31, 23, 59, 59)),
		issueEvent("acme/app", "created", at(time.September, 1, 0, 0, 0)),
		issueEvent("acme/cli", "created", at(time.September, 15, 9, 0, 0)),
		closedAs("completed", at(time.September, 30, 12, 0, 0)),
		issueEvent("acme/app", "created", at(time.October, 1, 0, 0, 0)),
	}
	type counts struct {
		date           time.Time
		new, completed int
	}
	want := []counts{
		{at(time.September, 1, 0, 0, 0), 2, 1},
		{at(time.August, 1, 0, 0, 0), 1, 0},
	}
	var got []counts
	for _, m := range IssueMonths(events, at(time.October, 14, 12, 0, 0), 2) {
		got = append(got, counts{m.Date, m.New, m.Completed})
	}
	if len(got) != len(want) {
		t.Fatalf("want the months\n%v\ngot\n%v", want, got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("row %d: want %v, got %v", i, want[i], got[i])
		}
	}
}

// TestIssueMonthsTotalIsTheIssuesOpenAtTheMonthsLastDay (forsgren#89, step 3):
// with now on 14 October and 2 months, the issues created in July are in the
// base: open when August begins. August ends with issues 2, 3 and 6 open (1 was
// closed), September ends with 2 and 4 (3 and 6 were closed), and issue 5, created
// in October, changes nothing.
func TestIssueMonthsTotalIsTheIssuesOpenAtTheMonthsLastDay(t *testing.T) {
	at := func(month time.Month, d int) time.Time {
		return time.Date(2026, month, d, 12, 0, 0, 0, time.UTC)
	}
	events := []history.IssueEvent{
		appEvent(1, "created", at(time.July, 3)),
		appEvent(2, "created", at(time.July, 20)),
		appEvent(3, "created", at(time.August, 10)),
		appEvent(6, "created", at(time.August, 15)),
		appEvent(1, "closed", at(time.August, 20)),
		appEvent(4, "created", at(time.September, 2)),
		appEvent(3, "closed", at(time.September, 5)),
		appEvent(6, "closed", at(time.September, 9)),
		appEvent(5, "created", at(time.October, 1)),
	}
	var got []int
	for _, m := range IssueMonths(events, at(time.October, 14), 2) {
		got = append(got, m.Total)
	}
	if want := []int{2, 3}; !slices.Equal(got, want) {
		t.Errorf("want the totals %v (September, August), got %v", want, got)
	}
}

// TestIssueMonthRowsGoBackToTheMonthOfTheOldestEvent (forsgren#89, step 5):
// with now on 14 October and the oldest event in July, the rows are
// September, August and July, newest first. August has no events, so it is a
// zero row that still carries the Total of 1, and the event in October, the
// current month, is no row.
func TestIssueMonthRowsGoBackToTheMonthOfTheOldestEvent(t *testing.T) {
	at := func(month time.Month, d int) time.Time {
		return time.Date(2026, month, d, 12, 0, 0, 0, time.UTC)
	}
	events := []history.IssueEvent{
		appEvent(1, "created", at(time.July, 3)),
		appEvent(2, "created", at(time.September, 2)),
		appEvent(3, "created", at(time.October, 1)),
	}
	type row struct {
		month      time.Month
		new, total int
	}
	want := []row{{time.September, 1, 2}, {time.August, 0, 1}, {time.July, 1, 1}}
	var got []row
	for _, m := range IssueMonthRows(events, at(time.October, 14)) {
		got = append(got, row{m.Date.Month(), m.New, m.Total})
	}
	if !slices.Equal(got, want) {
		t.Errorf("want the months %v, got %v", want, got)
	}
}

// TestIssueMonthRowsHaveNoRowsWithoutAnEventOrBeforeTheCurrentMonth
// (forsgren#89, step 6): no events give no rows, and neither do events that
// are all in the current month.
func TestIssueMonthRowsHaveNoRowsWithoutAnEventOrBeforeTheCurrentMonth(t *testing.T) {
	now := time.Date(2026, time.October, 14, 12, 0, 0, 0, time.UTC)
	inOctober := []history.IssueEvent{
		appEvent(1, "created", now.AddDate(0, 0, -3)),
		appEvent(2, "created", now.AddDate(0, 0, -13)),
	}
	if got := IssueMonthRows(nil, now); len(got) != 0 {
		t.Errorf("want no rows without events, got %v", got)
	}
	if got := IssueMonthRows(inOctober, now); len(got) != 0 {
		t.Errorf("want no rows when the oldest event is in the current month, got %v", got)
	}
}

// TestIssueMonthRowsAreActiveOnlyWhenSomethingHappened (forsgren#89, step 6):
// a reopened event alone makes its month Active (August), and a month with
// no event (September) is not. The Active flag comes from IssueDay.count.
func TestIssueMonthRowsAreActiveOnlyWhenSomethingHappened(t *testing.T) {
	now := time.Date(2026, time.October, 14, 12, 0, 0, 0, time.UTC)
	events := []history.IssueEvent{
		appEvent(1, "reopened", time.Date(2026, time.August, 3, 9, 0, 0, 0, time.UTC)),
	}
	var got []bool
	for _, m := range IssueMonthRows(events, now) {
		got = append(got, m.Active)
	}
	if want := []bool{false, true}; !slices.Equal(got, want) {
		t.Errorf("want Active %v (September, August), got %v", want, got)
	}
}

// TestIssueYearMonthsStopAtTheCurrentYear (forsgren#125, step 5): with now on
// 14 October 2026 and events from December 2025 on, the month rows are
// September back to January 2026, newest first, and the event in December
// 2025 is no row. With the oldest event in July 2026 they stop at July, and
// in January the current year holds no complete month.
func TestIssueYearMonthsStopAtTheCurrentYear(t *testing.T) {
	at := func(year int, month time.Month, d int) time.Time {
		return time.Date(year, month, d, 12, 0, 0, 0, time.UTC)
	}
	months := func(events []history.IssueEvent, now time.Time) []time.Month {
		var got []time.Month
		for _, m := range IssueYearMonths(events, now) {
			got = append(got, m.Date.Month())
		}
		return got
	}
	october := at(2026, time.October, 14)
	fromDecember := []history.IssueEvent{
		appEvent(1, "created", at(2025, time.December, 3)),
		appEvent(2, "created", at(2026, time.February, 2)),
	}
	want := []time.Month{9, 8, 7, 6, 5, 4, 3, 2, 1}
	if got := months(fromDecember, october); !slices.Equal(got, want) {
		t.Errorf("want the months %v, got %v", want, got)
	}
	fromJuly := []history.IssueEvent{appEvent(1, "created", at(2026, time.July, 3))}
	if got, want := months(fromJuly, october), []time.Month{9, 8, 7}; !slices.Equal(got, want) {
		t.Errorf("want the months %v, got %v", want, got)
	}
	if got := months(fromDecember, at(2026, time.January, 5)); len(got) != 0 {
		t.Errorf("want no months in January, got %v", got)
	}
}
