package metrics

import (
	"slices"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// TestIssueYearsCountsEachCompleteYearBeforeTheCurrentOne (forsgren#125, step
// 1): with now on 14 October 2026 and 2 years, the rows are 2025 and 2024,
// newest first, dated 1 January. 23:59:59 on 31 December and the next
// 00:00:00 land in different rows, both repositories count, a close counts in
// the column of its reason, and nothing in the current year counts.
func TestIssueYearsCountsEachCompleteYearBeforeTheCurrentOne(t *testing.T) {
	at := func(year int, month time.Month, d, h, m, s int) time.Time {
		return time.Date(year, month, d, h, m, s, 0, time.UTC)
	}
	events := []history.IssueEvent{
		issueEvent("acme/app", "created", at(2024, time.December, 31, 23, 59, 59)),
		issueEvent("acme/app", "created", at(2025, time.January, 1, 0, 0, 0)),
		issueEvent("acme/cli", "created", at(2025, time.June, 15, 9, 0, 0)),
		closedAs("completed", at(2025, time.December, 31, 12, 0, 0)),
		issueEvent("acme/app", "created", at(2026, time.January, 1, 0, 0, 0)),
	}
	type counts struct {
		date           time.Time
		new, completed int
	}
	want := []counts{
		{at(2025, time.January, 1, 0, 0, 0), 2, 1},
		{at(2024, time.January, 1, 0, 0, 0), 1, 0},
	}
	var got []counts
	for _, y := range IssueYears(events, at(2026, time.October, 14, 12, 0, 0), 2) {
		got = append(got, counts{y.Date, y.New, y.Completed})
	}
	if len(got) != len(want) {
		t.Fatalf("want the years\n%v\ngot\n%v", want, got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("row %d: want %v, got %v", i, want[i], got[i])
		}
	}
}

// TestIssueYearsTotalIsTheIssuesOpenAtTheYearsLastDay (forsgren#125, step 2):
// with now on 14 October 2026 and 2 years, the issues created in 2023 are in
// the base: open when 2024 begins. 2024 ends with issues 2 and 3 open (1 was
// closed), 2025 ends with 2, 4 and 6 (3 was closed), and issue 5, created in
// 2026, changes nothing.
func TestIssueYearsTotalIsTheIssuesOpenAtTheYearsLastDay(t *testing.T) {
	at := func(year int, month time.Month, d int) time.Time {
		return time.Date(year, month, d, 12, 0, 0, 0, time.UTC)
	}
	events := []history.IssueEvent{
		appEvent(1, "created", at(2023, time.July, 3)),
		appEvent(2, "created", at(2023, time.July, 20)),
		appEvent(3, "created", at(2024, time.March, 10)),
		appEvent(1, "closed", at(2024, time.December, 31)),
		appEvent(4, "created", at(2025, time.February, 2)),
		appEvent(3, "closed", at(2025, time.June, 5)),
		appEvent(6, "created", at(2025, time.December, 31)),
		appEvent(5, "created", at(2026, time.January, 1)),
	}
	var got []int
	for _, y := range IssueYears(events, at(2026, time.October, 14), 2) {
		got = append(got, y.Total)
	}
	if want := []int{3, 2}; !slices.Equal(got, want) {
		t.Errorf("want the totals %v (2025, 2024), got %v", want, got)
	}
}

// TestIssueYearRowsGoBackToTheYearOfTheOldestEventAndSkipTheCurrentYear
// (forsgren#125, step 3): with now on 14 October 2026 and the oldest event in
// 2023, the rows are 2025, 2024 and 2023, newest first. 2024 has no events, so
// it is a zero row that still carries the Total of 1, and the event in 2026,
// the current year, is no row. No events give no rows, and neither do events
// that are all in the current year.
func TestIssueYearRowsGoBackToTheYearOfTheOldestEventAndSkipTheCurrentYear(t *testing.T) {
	at := func(year int, month time.Month, d int) time.Time {
		return time.Date(year, month, d, 12, 0, 0, 0, time.UTC)
	}
	now := at(2026, time.October, 14)
	events := []history.IssueEvent{
		appEvent(3, "created", at(2026, time.January, 1)),
		appEvent(1, "created", at(2023, time.July, 3)),
		appEvent(2, "created", at(2025, time.September, 2)),
	}
	type row struct {
		year       int
		new, total int
	}
	want := []row{{2025, 1, 2}, {2024, 0, 1}, {2023, 1, 1}}
	var got []row
	for _, y := range IssueYearRows(events, now) {
		got = append(got, row{y.Date.Year(), y.New, y.Total})
	}
	if !slices.Equal(got, want) {
		t.Errorf("want the years %v, got %v", want, got)
	}
	if got := IssueYearRows(nil, now); len(got) != 0 {
		t.Errorf("want no rows without events, got %v", got)
	}
	inThisYear := []history.IssueEvent{appEvent(1, "created", at(2026, time.March, 3))}
	if got := IssueYearRows(inThisYear, now); len(got) != 0 {
		t.Errorf("want no rows when the oldest event is in the current year, got %v", got)
	}
}
