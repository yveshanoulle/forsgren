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
		if i, ok := newIssueRow(e, today, len(rows)); ok {
			rows[i].New++
		}
	}
	return rows
}

// utcDay is the midnight, UTC, that starts the calendar day t is in.
func utcDay(t time.Time) time.Time { return t.UTC().Truncate(day) }

// newIssueRow is the index, in rows days long and newest first, of the row
// that e counts as a new issue in; false for any event but a creation, and
// for one before the rows or on or after today.
func newIssueRow(e history.IssueEvent, today time.Time, rows int) (int, bool) {
	back := int(today.Sub(utcDay(e.At)) / day)
	return back - 1, e.Event == "created" && back >= 1 && back <= rows
}
