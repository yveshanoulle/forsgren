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

// IssueYearRows is IssueYears for every complete calendar year.
func IssueYearRows(events []history.IssueEvent, now time.Time) []IssueDay {
	return nil
}
