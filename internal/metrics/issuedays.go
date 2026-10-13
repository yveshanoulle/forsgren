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
	// Active is whether anything happened on that day: a new issue, a close
	// of any kind, or a reopen (forsgren#108).
	Active bool
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
		if i, ok := dayRow(e.At, today, len(rows)); ok {
			rows[i].count(e)
		}
	}
	perDay, openAtStart := openChanges(events, today, len(rows))
	addUpTotals(rows, perDay, openAtStart)
	return rows
}

// openChanges is what the events do to the issues open, by openDelta: per row
// of a table rows days long ending the day before today, newest first, the
// net change on that row's day, and the issues open when the oldest row's day
// begins, from the events before it. Events today or later change nothing.
func openChanges(events []history.IssueEvent, today time.Time, rows int) (perDay []int, openAtStart int) {
	created := createdIssues(events)
	perDay = make([]int, rows)
	start := today.Add(-time.Duration(rows) * day)
	for _, e := range events {
		if i, ok := dayRow(e.At, today, rows); ok {
			perDay[i] += openDelta(e, created)
		} else if e.At.Before(start) {
			openAtStart += openDelta(e, created)
		}
	}
	return perDay, openAtStart
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
// openAtStart, open when the oldest row's day begins, plus the perDay change
// of each day up to it, from the oldest row on. rows are newest first, as is
// perDay.
func addUpTotals(rows []IssueDay, perDay []int, openAtStart int) {
	total := openAtStart
	for i := len(rows) - 1; i >= 0; i-- {
		total += perDay[i]
		rows[i].Total = total
	}
}

// count adds e to d: a created event is a new issue, a closed event one in
// the column of its reason, anything else nothing. A created, a closed and a
// reopened event all make the day Active (a reopen changes the Total).
func (d *IssueDay) count(e history.IssueEvent) {
	switch e.Event {
	case history.EventCreated:
		d.New++
		d.Active = true
	case history.EventClosed:
		*d.closedColumn(e.Reason)++
		d.Active = true
	case history.EventReopened:
		d.Active = true
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
