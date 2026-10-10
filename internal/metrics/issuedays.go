package metrics

// The issue counts of the page's daily table (forsgren#76): per UTC calendar
// day, how many issues were opened and how many were completed, of all the
// tracked repositories together, from the events collect stored
// (history.IssueEvent).

import (
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// IssueDay is one UTC calendar day of the table.
type IssueDay struct {
	// Date is the day's midnight, UTC.
	Date time.Time
	// New is the issues created on that day. A reopened issue is not new.
	New int
	// Completed is the issues closed as completed on that day. Other close
	// reasons are not completed.
	Completed int
}

// IssueDays is the last days UTC calendar days before the day of now, today
// left out, newest first: the first row is yesterday, the page's order. A
// day without events is a row of zeros. Every repository in events counts.
func IssueDays(events []history.IssueEvent, now time.Time, days int) []IssueDay {
	today := utcDay(now)
	rows := make([]IssueDay, max(days, 0))
	for i := range rows {
		rows[i].Date = today.Add(-time.Duration(i+1) * day)
	}
	for _, e := range events {
		i, ok := dayRow(e.At, today, len(rows))
		if !ok {
			continue
		}
		rows[i].count(e)
	}
	return rows
}

// count adds e to d: a created event is a new issue, a closed event with
// the reason completed a completed one, anything else nothing.
func (d *IssueDay) count(e history.IssueEvent) {
	switch {
	case e.Event == history.EventCreated:
		d.New++
	case e.Event == history.EventClosed && e.Reason == history.ReasonCompleted:
		d.Completed++
	}
}

// utcDay is the midnight, UTC, that starts the calendar day t is in.
func utcDay(t time.Time) time.Time { return t.UTC().Truncate(day) }

// dayRow is the index, in rows days long and newest first, of the row of
// the day at is in, today being the midnight that starts today; false for a
// time before the rows or on or after today.
func dayRow(at, today time.Time, rows int) (int, bool) {
	back := int(today.Sub(utcDay(at)) / day)
	return back - 1, back >= 1 && back <= rows
}
