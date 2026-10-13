package metrics

// The issues page's monthly rows (forsgren#89, decision #118): per UTC
// calendar month, the same counts as IssueDays gives per day.

import (
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// IssueMonths is the months complete calendar months UTC before the month of
// now, newest first: the current month is left out. Each row's Date is the
// month's first day at midnight, UTC.
func IssueMonths(events []history.IssueEvent, now time.Time, months int) []IssueDay {
	return nil
}
