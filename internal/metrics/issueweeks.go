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
	return nil
}
