package metrics

// The issue counts of the page's daily table (forsgren#76): per UTC calendar
// day, how many issues were opened and how many were closed, by the reason of
// the close, of all the tracked repositories together, from the events
// collect stored (history.IssueEvent).

import (
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// IssueDay is one UTC calendar day of the table, its fields in the order of
// the issues page's columns. Every close lands in exactly one of Completed,
// NotPlanned, Duplicate and Other (closedColumn).
type IssueDay struct {
	// Date is the day's midnight, UTC.
	Date time.Time
	// New is the issues created on that day. A reopened issue is not new.
	New int
	// Completed is the issues closed as completed on that day.
	Completed int
	// NotPlanned is the issues closed as not planned on that day.
	NotPlanned int
	// Duplicate is the issues closed as duplicates on that day.
	Duplicate int
	// Other is the issues closed on that day with no reason, or a reason
	// forsgren does not know.
	Other int
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

// count adds e to d: a created event is a new issue, a closed event one in
// the column of its reason, anything else nothing.
func (d *IssueDay) count(e history.IssueEvent) {
	switch e.Event {
	case history.EventCreated:
		d.New++
	case history.EventClosed:
		*d.closedColumn(e.Reason)++
	}
}

// closedColumn is the count that a close with reason adds to: the column of
// a reason forsgren knows, else Other, so every close lands in exactly one.
func (d *IssueDay) closedColumn(reason string) *int {
	switch reason {
	case history.ReasonCompleted:
		return &d.Completed
	case history.ReasonNotPlanned:
		return &d.NotPlanned
	case history.ReasonDuplicate:
		return &d.Duplicate
	}
	return &d.Other
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
