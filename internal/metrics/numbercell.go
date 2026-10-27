package metrics

// The cells of the numbers view (forsgren#46): each metric's number only,
// no band; "-" where there is no number, 0 where the count is really zero.

import (
	"fmt"
)

// noNumber is the cell of a metric with no number.
const noNumber = "-"

// NumberCell is the successful deployments of the DORA window, 0 if none.
func (f Frequency) NumberCell() string { return GroupDigits(f.ofWindow().deployments) }

// WeekendNumberCell is how many of the successful deployments of the DORA
// window, the window NumberCell counts, were created on a Saturday or a
// Sunday, UTC; 0 if none (forsgren#124).
func (f Frequency) WeekendNumberCell() string { return GroupDigits(f.ofWindow().weekends) }

// NumberCell is the median as the standard cell shows it, "2 h 7 min", "-"
// without commits.
func (l LeadTime) NumberCell() string {
	if !l.HasCommits() {
		return noNumber
	}
	return shortDuration(l.Median)
}

// NumberCell is the median of the completed recoveries, "-" with none
// completed, whether runs of failures are still open or there are none.
func (r Recovery) NumberCell() string {
	if r.Recoveries == 0 {
		return noNumber
	}
	return shortDuration(r.Median)
}

// NumberCell is the rate in whole percent, "14%", "-" without deployments.
func (r ChangeFailRate) NumberCell() string {
	if r.Deployments == 0 {
		return noNumber
	}
	return percentCell(r.Percent())
}

// NumberCell is the rate in whole percent, "14%", "-" without successful
// deployments.
func (r ReworkRate) NumberCell() string {
	if r.Deployments == 0 {
		return noNumber
	}
	return percentCell(r.Percent())
}

// percentCell is a rate in whole percent.
func percentCell(percent int) string { return fmt.Sprintf("%d%%", percent) }
