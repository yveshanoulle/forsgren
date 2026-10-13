package metrics

// The issues page's rows of every kind (forsgren#89, #123, #128, decision #118): the
// days of the current week, then the complete weeks of the month, then the
// complete months of the year, then the complete years (forsgren#125).

import (
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// The kinds of an IssueRow, which tell the page how to label its Date.
const (
	KindDay   = "day"
	KindWeek  = "week"
	KindMonth = "month"
	KindYear  = "year"
)

// IssueRow is an IssueDay of one of the kinds, so the page can label it: a
// day by its date, a week by the ISO number of its Monday, a month by its
// name and year, a year by the year.
type IssueRow struct {
	Kind string
	IssueDay
}

// IssueRows is the days of the current week up to yesterday, then the
// complete weeks touching the current month, then the complete months of the
// current year, then every earlier complete year back to the oldest event, each
// newest first (IssueWeekDays, IssueWeeks, IssueYearMonths and IssueYearRows).
func IssueRows(events []history.IssueEvent, now time.Time) []IssueRow {
	rows := kindRows(KindDay, IssueWeekDays(events, now))
	rows = append(rows, kindRows(KindWeek, IssueWeeks(events, now))...)
	rows = append(rows, kindRows(KindMonth, IssueYearMonths(events, now))...)
	return append(rows, kindRows(KindYear, IssueYearRows(events, now))...)
}

// kindRows is days as rows of kind.
func kindRows(kind string, days []IssueDay) []IssueRow {
	rows := make([]IssueRow, len(days))
	for i, d := range days {
		rows[i] = IssueRow{Kind: kind, IssueDay: d}
	}
	return rows
}
