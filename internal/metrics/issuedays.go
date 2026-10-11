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
	// Total is the issues open at the end of that day, of all the tracked
	// repositories: created up to then and not closed since.
	Total int
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
	created := createdIssues(events)
	seen := map[history.IssueKey]bool{} // MUTATION 76-38a: removed in 76-38b
	opened := make([]int, len(rows))
	for _, e := range events {
		i, ok := dayRow(e.At, today, len(rows))
		if !ok {
			continue
		}
		rows[i].count(e)
		seen[e.IssueKey()] = seen[e.IssueKey()] || e.Event == history.EventCreated
		opened[i] += openDelta(e, seen)
	}
	start := today.Add(-time.Duration(len(rows)) * day)
	addUpTotals(rows, opened, openedBefore(events, created, start))
	return rows
}

// createdIssues are the issues with a created event in events.
func createdIssues(events []history.IssueEvent) map[history.IssueKey]bool {
	created := map[history.IssueKey]bool{}
	for _, e := range events {
		if e.Event == history.EventCreated {
			created[e.IssueKey()] = true
		}
	}
	return created
}

// openedBefore is how many issues the events before start leave open, by
// openDelta. It is the base of the oldest row's Total.
func openedBefore(events []history.IssueEvent, created map[history.IssueKey]bool, start time.Time) int {
	open := 0
	for _, e := range events {
		if e.At.Before(start) {
			open += openDelta(e, created)
		}
	}
	return open
}

// openDelta is what e adds to the issues open: one for a created or a
// reopened event, minus one for the close of an issue that has a created
// event; a close of an issue never seen created lowers nothing.
func openDelta(e history.IssueEvent, created map[history.IssueKey]bool) int {
	switch {
	case e.Event == history.EventCreated, e.Event == history.EventReopened:
		return 1
	case e.Event == history.EventClosed && created[e.IssueKey()]:
		return -1
	}
	return 0
}

// addUpTotals sets each row's Total, the issues open at the end of its day:
// open when the oldest row's day begins, plus what each day opened (the
// openDelta of its events), from the oldest row on. rows are newest first, as
// is opened.
func addUpTotals(rows []IssueDay, opened []int, open int) {
	total := open
	for i := len(rows) - 1; i >= 0; i-- {
		total += opened[i]
		rows[i].Total = total
	}
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
