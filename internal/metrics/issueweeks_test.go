package metrics

import (
	"slices"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// TestIssueWeeksAreTheCompleteWeeksTouchingTheCurrentMonth (forsgren#89,
// step 7): with now on Wednesday 14 October 2026, the rows are week 41 (Monday
// 5 October) and week 40 (Monday 28 September, which reaches into
// September), newest first. Sunday 27 September, week 39, is no row but is in
// the base of the Totals, 23:59:59 on Sunday 4 October is in week 40, and
// the event of the current week (12 October) is no row.
func TestIssueWeeksAreTheCompleteWeeksTouchingTheCurrentMonth(t *testing.T) {
	at := func(month time.Month, d, h, m, s int) time.Time {
		return time.Date(2026, month, d, h, m, s, 0, time.UTC)
	}
	event := func(issue int64, name, reason string, when time.Time) history.IssueEvent {
		return history.IssueEvent{Repository: "acme/app", Issue: issue, Event: name, Reason: reason, At: when}
	}
	events := []history.IssueEvent{
		event(1, "created", "", at(time.September, 27, 12, 0, 0)),
		event(2, "created", "", at(time.September, 28, 0, 0, 0)),
		event(3, "created", "", at(time.October, 4, 23, 59, 59)),
		event(4, "created", "", at(time.October, 5, 0, 0, 0)),
		event(2, "closed", "completed", at(time.October, 11, 8, 0, 0)),
		event(5, "created", "", at(time.October, 12, 9, 0, 0)),
	}
	type row struct {
		monday                time.Time
		new, completed, total int
	}
	want := []row{
		{at(time.October, 5, 0, 0, 0), 1, 1, 3},
		{at(time.September, 28, 0, 0, 0), 2, 0, 3},
	}
	var got []row
	for _, w := range IssueWeeks(events, at(time.October, 14, 12, 0, 0)) {
		got = append(got, row{w.Date, w.New, w.Completed, w.Total})
	}
	if !slices.Equal(got, want) {
		t.Errorf("want the weeks\n%v\ngot\n%v", want, got)
	}
}
