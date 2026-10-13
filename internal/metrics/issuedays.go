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
// the columns of the issues and months pages; a week's or a month's row (forsgren#89) has the
// same counts over its period, "that day" below meaning that period. Every close lands in exactly one of Completed,
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
	// repositories: the created and reopened events up to then less the
	// closed ones, each counted by openDelta (forsgren#122).
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
	return periodRows(events, days,
		func(i int) time.Time { return today.Add(-time.Duration(i+1) * day) },
		func(at time.Time) (int, bool) { return dayRow(at, today, days) })
}

// periodRows is n rows of back-to-back periods (days, weeks or months),
// newest first, row i dated dateOf(i), the start of its period; none for n 0
// or less. Each event counts on the row rowOf gives its time, and each row's
// Total is the issues open at the end of its period.
func periodRows(
	events []history.IssueEvent, n int, dateOf func(int) time.Time, rowOf func(time.Time) (int, bool),
) []IssueDay {
	rows := make([]IssueDay, max(n, 0))
	for i := range rows {
		rows[i].Date = dateOf(i)
	}
	for _, e := range events {
		if i, ok := rowOf(e.At); ok {
			rows[i].count(e)
		}
	}
	perRow, openAtStart := openChanges(events, dateOf(len(rows)-1), len(rows), rowOf)
	addUpTotals(rows, perRow, openAtStart)
	return rows
}

// openChanges is what the events do to the issues open, by openDelta: per
// row of a table rows long, newest first, the net change on that row's
// period (rowOf gives an event time's row), and the issues open when the
// oldest row's period begins at start, from the events before it. Events after
// the newest row change nothing.
func openChanges(
	events []history.IssueEvent, start time.Time, rows int, rowOf func(time.Time) (int, bool),
) (perRow []int, openAtStart int) {
	perRow = make([]int, rows)
	for _, e := range events {
		if i, ok := rowOf(e.At); ok {
			perRow[i] += openDelta(e)
		} else if e.At.Before(start) {
			openAtStart += openDelta(e)
		}
	}
	return perRow, openAtStart
}

// openDelta is what e adds to the issues open: one for a created event and
// for a reopened one, one less for a closed one, whether or not the issue has
// a created event in the list (forsgren#122, overruling #113 and #120).
func openDelta(e history.IssueEvent) int {
	switch e.Event {
	case history.EventCreated, history.EventReopened:
		return 1
	case history.EventClosed:
		return -1
	}
	return 0
}

// addUpTotals sets each row's Total, the issues open at the end of its
// period: openAtStart, open when the oldest row's period begins, plus the
// perRow change of each period up to it, from the oldest row on. rows are
// newest first, as is perRow.
func addUpTotals(rows []IssueDay, perRow []int, openAtStart int) {
	total := openAtStart
	for i := len(rows) - 1; i >= 0; i-- {
		total += perRow[i]
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
	return rowBack(int(today.Sub(utcDay(at))/day), rows)
}

// rowBack is the index, in rows periods long and newest first, of the row of
// the period back periods before the current one (one being the newest row);
// false for the current period or later (back below one) or a period before
// the rows (back above rows). Every period's row function (dayRow, weekRow,
// monthRow, yearRow) counts back and leaves the bounds to it.
func rowBack(back, rows int) (int, bool) {
	return back - 1, back >= 1 && back <= rows
}

// oldestAt is the time of the oldest of events; false when there are none.
// IssueMonthRows and IssueYearRows reach back to it.
func oldestAt(events []history.IssueEvent) (time.Time, bool) {
	if len(events) == 0 {
		return time.Time{}, false
	}
	oldest := events[0].At
	for _, e := range events {
		if e.At.Before(oldest) {
			oldest = e.At
		}
	}
	return oldest, true
}
