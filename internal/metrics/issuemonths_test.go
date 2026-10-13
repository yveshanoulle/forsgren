package metrics

import (
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
