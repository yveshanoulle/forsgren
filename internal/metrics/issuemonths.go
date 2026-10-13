package metrics

// The issues page's monthly rows (forsgren#89, decision #118): per UTC
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
	rows := make([]IssueDay, max(months, 0))
	for i := range rows {
		rows[i].Date = current.AddDate(0, -(i + 1), 0)
	}
	for _, e := range events {
		if i, ok := monthRow(e.At, current, len(rows)); ok {
			rows[i].count(e)
		}
	}
	start := current.AddDate(0, -len(rows), 0)
	perMonth, openAtStart := openChanges(events, start, len(rows), func(at time.Time) (int, bool) {
		return monthRow(at, current, len(rows))
	})
	addUpTotals(rows, perMonth, openAtStart)
	return rows
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
	at = at.UTC()
	back := (current.Year()-at.Year())*12 + int(current.Month()-at.Month())
	return back - 1, back >= 1 && back <= rows
}

// IssueMonthRows is every complete calendar month from the month of the
// oldest event to the month before the one of now, newest first, a month
// without events a zero row (carrying the Total); none when there are no
// events or the oldest is in the current month.
func IssueMonthRows(events []history.IssueEvent, now time.Time) []IssueDay {
	return nil
}
