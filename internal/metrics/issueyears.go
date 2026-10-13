package metrics

// The months page's yearly rows (forsgren#125): per UTC calendar year, the
// same counts as IssueDays gives per day.

import (
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// IssueYears is the years complete calendar years UTC before the year of now,
// newest first: the current year is left out. Each row's Date is the year's
// first day at midnight, UTC.
func IssueYears(events []history.IssueEvent, now time.Time, years int) []IssueDay {
	current := now.UTC().Year()
	return periodRows(events, years,
		func(i int) time.Time { return time.Date(current-i-1, time.January, 1, 0, 0, 0, 0, time.UTC) },
		func(at time.Time) (int, bool) { return yearRow(at, current, years) })
}

// yearRow is the index, in rows years long and newest first, of the row of
// the year at is in, current being the current year; false for a time before
// the rows or in the current year or later.
func yearRow(at time.Time, current, rows int) (int, bool) {
	back := current - at.UTC().Year()
	return back - 1, back >= 1 && back <= rows
}

// IssueYearRows is every complete calendar year from the year of the oldest
// event to the year before the one of now, newest first, a year without
// events a zero row (carrying the Total); none when there are no events or the
// oldest is in the current year.
func IssueYearRows(events []history.IssueEvent, now time.Time) []IssueDay {
	if len(events) == 0 {
		return nil
	}
	oldest := events[0].At
	for _, e := range events {
		if e.At.Before(oldest) {
			oldest = e.At
		}
	}
	return IssueYears(events, now, now.UTC().Year()-oldest.UTC().Year())
}
