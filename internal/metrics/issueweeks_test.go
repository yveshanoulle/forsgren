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

// TestIssueWeekDaysAreTheDaysOfTheCurrentWeekUpToYesterday (forsgren#89,
// step 9): with now on Wednesday 14 October 2026, the rows are Tuesday 13 and
// Monday 12, newest first, as IssueDays counts them. Sunday 11 October, last
// week, is in the base of the Totals but no row, and nothing today is a row.
func TestIssueWeekDaysAreTheDaysOfTheCurrentWeekUpToYesterday(t *testing.T) {
	event := func(issue int64, name, reason string, d, h int) history.IssueEvent {
		at := time.Date(2026, time.October, d, h, 0, 0, 0, time.UTC)
		return history.IssueEvent{Repository: "acme/app", Issue: issue, Event: name, Reason: reason, At: at}
	}
	events := []history.IssueEvent{
		event(1, "created", "", 11, 12),
		event(2, "created", "", 12, 9),
		event(1, "closed", "not_planned", 13, 9),
		event(3, "created", "", 14, 9),
	}
	type row struct {
		day                    int
		new, notPlanned, total int
	}
	want := []row{{13, 0, 1, 1}, {12, 1, 0, 2}}
	var got []row
	for _, d := range IssueWeekDays(events, time.Date(2026, time.October, 14, 12, 0, 0, 0, time.UTC)) {
		got = append(got, row{d.Date.Day(), d.New, d.NotPlanned, d.Total})
	}
	if !slices.Equal(got, want) {
		t.Errorf("want the days %v, got %v", want, got)
	}
}

// TestIssueWeekDaysAreNoneOnAMonday (forsgren#89, step 10): on Monday 12
// October 2026 the current week has no day before today, so there is no row,
// whatever the events.
func TestIssueWeekDaysAreNoneOnAMonday(t *testing.T) {
	created := time.Date(2026, time.October, 11, 12, 0, 0, 0, time.UTC)
	events := []history.IssueEvent{{Repository: "acme/app", Issue: 1, Event: "created", At: created}}
	monday := time.Date(2026, time.October, 12, 12, 0, 0, 0, time.UTC)
	if got := IssueWeekDays(events, monday); len(got) != 0 {
		t.Errorf("want no days on a Monday, got %v", got)
	}
}
