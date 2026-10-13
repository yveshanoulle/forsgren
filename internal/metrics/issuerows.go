package metrics

// The issues page's rows of every kind (forsgren#89, decision #118): the
// days of the current week, then the complete weeks of the month, then the
// complete months.

import (
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// The kinds of an IssueRow, which tell the page how to label its Date.
const (
	KindDay   = "day"
	KindWeek  = "week"
	KindMonth = "month"
)

// IssueRow is an IssueDay of one of the kinds, so the page can label it: a
// day by its date, a week by the ISO number of its Monday, a month by its
// name and year.
type IssueRow struct {
	Kind string
	IssueDay
}

// IssueRows is the days of the current week up to yesterday, then the
// complete weeks touching the current month, then every complete month back to
// the oldest event, each newest first (IssueWeekDays, IssueWeeks and
// IssueMonthRows).
func IssueRows(events []history.IssueEvent, now time.Time) []IssueRow {
	return nil
}
