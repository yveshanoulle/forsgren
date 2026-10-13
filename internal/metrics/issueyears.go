package metrics

// The months page's yearly rows (forsgren#125): per UTC calendar year, the
// same counts as IssueDays gives per day.

import (
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// IssueYears is the years complete calendar years UTC before the year of now,
// newest first. Each row's Date is the year's first day at midnight, UTC.
func IssueYears(events []history.IssueEvent, now time.Time, years int) []IssueDay {
	return nil
}
