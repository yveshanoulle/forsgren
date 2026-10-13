package metrics

// The months page's monthly rows (forsgren#89, #123, decision #118): per UTC
// calendar month, the same counts as IssueDays gives per day.

import (
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// IssueMonths is the months complete calendar months UTC before the month of
// now, newest first: the current month is left out. Each row's Date is the
// month's first day at midnight, UTC.
func IssueMonths(events []history.IssueEvent, now time.Time, months int) []IssueDay {
	current := monthStart(now)
	return periodRows(events, months,
		func(i int) time.Time { return current.AddDate(0, -(i + 1), 0) },
		func(at time.Time) (int, bool) { return monthRow(at, current, months) })
}

// monthStart is the midnight, UTC, that starts the calendar month t is in.
func monthStart(t time.Time) time.Time {
	t = t.UTC()
	return time.Date(t.Year(), t.Month(), 1, 0, 0, 0, 0, time.UTC)
}

// monthRow is the index, in rows months long and newest first, of the row of
// the month at is in, current being the first day of the current month; false
// for a time before the rows or in the current month or later.
func monthRow(at, current time.Time, rows int) (int, bool) {
	back := monthsBefore(at, current)
	return back - 1, back >= 1 && back <= rows
}

// monthsBefore is how many calendar months the month at is in lies before
// current, the first day of a month; negative for a later month.
func monthsBefore(at, current time.Time) int {
	at = at.UTC()
	return (current.Year()-at.Year())*12 + int(current.Month()-at.Month())
}

// IssueMonthRows is every complete calendar month from the month of the
// oldest event to the month before the one of now, newest first, a month
// without events a zero row (carrying the Total); none when there are no
// events or the oldest is in the current month.
func IssueMonthRows(events []history.IssueEvent, now time.Time) []IssueDay {
	if len(events) == 0 {
		return nil
	}
	oldest := events[0].At
	for _, e := range events {
		if e.At.Before(oldest) {
			oldest = e.At
		}
	}
	current := monthStart(now)
	return IssueMonths(events, now, monthsBefore(oldest, current))
}
