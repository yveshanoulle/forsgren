package metrics

// The issues page's weekly rows (forsgren#89, decision #118): per Monday to
// Sunday week, UTC, the same counts as IssueDays gives per day.

import (
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// IssueWeeks is the complete weeks, Monday to Sunday, that touch the month of
// now and end before the current week, newest first: the current week is not
// a row (its days are). Each row's Date is the week's Monday at midnight, UTC.
func IssueWeeks(events []history.IssueEvent, now time.Time) []IssueDay {
	monday := weekStart(now)
	weeks := int(monday.Sub(weekStart(monthStart(now))) / week)
	rows := make([]IssueDay, weeks)
	for i := range rows {
		rows[i].Date = monday.Add(-time.Duration(i+1) * week)
	}
	rowOf := func(at time.Time) (int, bool) { return weekRow(at, monday, weeks) }
	for _, e := range events {
		if i, ok := rowOf(e.At); ok {
			rows[i].count(e)
		}
	}
	perWeek, openAtStart := openChanges(events, monday.Add(-time.Duration(weeks)*week), weeks, rowOf)
	addUpTotals(rows, perWeek, openAtStart)
	return rows
}

// week is the length of a Monday to Sunday week.
const week = 7 * day

// weekStart is the Monday, at midnight UTC, that starts the week t is in.
func weekStart(t time.Time) time.Time {
	d := utcDay(t)
	return d.AddDate(0, 0, -int((d.Weekday()+6)%7))
}

// weekRow is the index, in rows weeks long and newest first, of the row of the
// week at is in, monday being the Monday that starts the current week; false
// for a time before the rows or in the current week or later.
func weekRow(at, monday time.Time, rows int) (int, bool) {
	back := int(monday.Sub(weekStart(at)) / week)
	return back - 1, back >= 1 && back <= rows
}

// IssueWeekDays is the days of the current week, Monday to yesterday, newest
// first, as IssueDays gives them: none on a Monday, today never a row.
func IssueWeekDays(events []history.IssueEvent, now time.Time) []IssueDay {
	return IssueDays(events, now, int(utcDay(now).Sub(weekStart(now))/day))
}
