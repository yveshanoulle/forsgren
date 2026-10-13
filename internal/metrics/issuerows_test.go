package metrics

import (
	"slices"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// TestIssueRowsListDaysThenWeeksThenMonths (forsgren#89, step 11): with now
// on Wednesday 14 October 2026 and an event in each period, the rows are
// Tuesday 13 and Monday 12, then week 41 (Monday 5 October) and week 40
// (Monday 28 September), then September and August, each with its kind.
func TestIssueRowsListDaysThenWeeksThenMonths(t *testing.T) {
	at := func(month time.Month, d int) time.Time {
		return time.Date(2026, month, d, 12, 0, 0, 0, time.UTC)
	}
	var events []history.IssueEvent
	for i, when := range []time.Time{
		at(time.October, 13), at(time.October, 6), at(time.September, 29),
		at(time.September, 10), at(time.August, 20),
	} {
		events = append(events, history.IssueEvent{Repository: "acme/app", Issue: int64(i + 1), Event: "created", At: when})
	}
	type row struct {
		kind  string
		month time.Month
		day   int
	}
	want := []row{
		{KindDay, time.October, 13}, {KindDay, time.October, 12},
		{KindWeek, time.October, 5}, {KindWeek, time.September, 28},
		{KindMonth, time.September, 1}, {KindMonth, time.August, 1},
	}
	var got []row
	for _, r := range IssueRows(events, at(time.October, 14)) {
		got = append(got, row{r.Kind, r.Date.Month(), r.Date.Day()})
	}
	if !slices.Equal(got, want) {
		t.Errorf("want the rows\n%v\ngot\n%v", want, got)
	}
}
