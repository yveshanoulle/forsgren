package metrics

// The issue counts of the page's daily table (forsgren#76): per UTC calendar
// day, how many issues were opened and how many were closed, by the reason of
// the close, of all the tracked repositories together, from the events
// collect stored (history.IssueEvent).

import (
	"fmt"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// IssueDay is one UTC calendar day of the table, its fields in the order of
// the columns of the days and issues pages (forsgren#128); a week's or a month's row (forsgren#89) has the
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
	// Open is the issues open at the end of that day, of all the tracked
	// repositories: the created and reopened events up to then less the
	// closed ones, each counted by openDelta (forsgren#122).
	Open int
	// Total is the issues created up to the end of that day, of all the tracked
	// repositories, open or closed: the created events up to then (forsgren#134).
	// A reopen adds none, the issue already counts.
	Total int
	// OpenBugs is the issues open at the end of that day that carry the bug
	// label: the Open of the events whose issue is a bug (forsgren#126).
	OpenBugs int
	// OpenChange is how much Open moved over that period: Open at its end less
	// Open at the end of the period before, negative when it fell. Its
	// direction is OpenTrend (forsgren#126).
	OpenChange int
	// Active is whether anything happened on that day: a new issue, a close
	// of any kind, or a reopen (forsgren#108).
	Active bool
}

// Trend is which way a count of open issues moved from the end of one period
// to the end of the next: Flat when it did not change, Up when it rose, Down
// when it fell. It says only whether the count rose or fell, not whether that
// is better (forsgren#126, forsgren#114).
type Trend int

// The directions of a Trend; Flat is the zero value.
const (
	TrendFlat Trend = iota
	TrendUp
	TrendDown
)

// OpenTrend is the direction of d's Open from the end of the period before.
func (d IssueDay) OpenTrend() Trend { return trendOf(d.OpenChange) }

// trendOf is Up for a change above zero, Down for one below, else Flat.
func trendOf(change int) Trend {
	switch {
	case change > 0:
		return TrendUp
	case change < 0:
		return TrendDown
	}
	return TrendFlat
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

// periodRows is n rows of back-to-back periods (days, weeks, months or years),
// newest first, row i dated dateOf(i), the start of its period; none for n 0
// or less. Each event counts on the row rowOf gives its time, each row's
// Open is the issues open at the end of its period, and its Total the issues
// created up to the end of it (forsgren#134).
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
	start := dateOf(len(rows) - 1)
	for _, c := range runningCounts {
		perRow, atStart := periodChanges(events, start, len(rows), rowOf, c.delta)
		addUp(rows, perRow, atStart, c)
	}
	return rows
}

// runningCount is a column that counts up over time rather than per period:
// what each event adds to it (delta), where a row keeps it (column) and, when
// the column has a trend, where it keeps how much the count moved over the
// row's period (change, nil for none).
type runningCount struct {
	delta  func(history.IssueEvent) int
	column func(*IssueDay) *int
	change func(*IssueDay) *int
}

// runningCounts are the columns periodRows adds up from the oldest row on, each
// at the end of its row's period: Open by openDelta (forsgren#122), Total by
// createdDelta (forsgren#134) and OpenBugs by bugDelta (forsgren#126).
var runningCounts = []runningCount{
	{openDelta, func(d *IssueDay) *int { return &d.Open }, func(d *IssueDay) *int { return &d.OpenChange }},
	{createdDelta, func(d *IssueDay) *int { return &d.Total }, nil},
	{bugDelta, func(d *IssueDay) *int { return &d.OpenBugs }, nil},
}

// periodChanges is what the events do to a count, by delta: per row of a
// table rows long, newest first, the net change on that row's period (rowOf
// gives an event time's row), and the count when the oldest row's period
// begins at start, from the events before it. Events after the newest row
// change nothing.
func periodChanges(
	events []history.IssueEvent, start time.Time, rows int, rowOf func(time.Time) (int, bool),
	delta func(history.IssueEvent) int,
) (perRow []int, atStart int) {
	perRow = make([]int, rows)
	for _, e := range events {
		if i, ok := rowOf(e.At); ok {
			perRow[i] += delta(e)
		} else if e.At.Before(start) {
			atStart += delta(e)
		}
	}
	return perRow, atStart
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

// bugDelta is what e adds to the open bugs: what openDelta gives for an event
// of an issue that carries the bug label, nothing for any other (forsgren#126).
func bugDelta(e history.IssueEvent) int {
	if !e.Bug {
		return 0
	}
	return openDelta(e)
}

// createdDelta is what e adds to the issues created: one for a created event,
// nothing for any other, so a reopen adds none and a close of an issue with no
// created event in the list adds none (forsgren#134).
func createdDelta(e history.IssueEvent) int {
	if e.Event == history.EventCreated {
		return 1
	}
	return 0
}

// addUp sets the count that column picks in each row, at the end of its
// period: atStart, the count when the oldest row's period begins, plus the
// perRow change of each period up to it, from the oldest row on. rows are
// newest first, as is perRow. When c has a change, each row also keeps its own
// perRow change there: the move from the end of the period before, the oldest
// row's from atStart.
func addUp(rows []IssueDay, perRow []int, atStart int, c runningCount) {
	running := atStart
	for i := len(rows) - 1; i >= 0; i-- {
		running += perRow[i]
		*c.column(&rows[i]) = running
		if c.change != nil {
			*c.change(&rows[i]) = perRow[i]
		}
	}
}

// count adds e to d: a created event is a new issue, a closed event one in
// the column of its reason, anything else nothing. A created, a closed and a
// reopened event all make the day Active (a reopen changes the Open).
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

// OpenShare is the issues open out of the issues created, Open out of Total
// (forsgren#134), as a whole percent rounded down, "—" when Total is 0.
func (d IssueDay) OpenShare() string {
	if d.Total == 0 {
		return "—"
	}
	return fmt.Sprintf("%d%%", d.Open*100/d.Total)
}
