package metrics

import (
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
