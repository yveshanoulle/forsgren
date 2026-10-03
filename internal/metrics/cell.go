package metrics

// The cells of the page's table (forsgren#38): each metric in short, its
// DORA band first, then the number that decided it and the count it is
// over, "Less than one day · 2 h 7 min (48)". The legend under the table
// says what each counts and over which window.

import (
	"fmt"
	"strconv"
	"time"
)

// cellSeparator separates the parts of a cell.
const cellSeparator = " · "

// Cell is the band and the count that decided it, the last 30 days' or,
// with none in them, the last 180 days': "Between once per day and once per
// week · 7"; a row whose deployments all failed shows its band of none,
// "Less than once per six months · 0" (decision #35).
func (f Frequency) Cell() string {
	count := f.Last30
	if count == 0 {
		count = f.Last180
	}
	return cell(f.Band, strconv.Itoa(count))
}

// Cell is the band, the median and the count of commits, "Less than one
// day · 2 h 7 min (48)"; "No lead time yet" without commits.
func (l LeadTime) Cell() string {
	if !l.HasCommits() {
		return "No lead time yet"
	}
	return cell(l.Band, timed(l.Median, l.Commits))
}

// Cell is the band, the median and the count of recoveries, then the
// recoveries not completed yet, "Less than one day · 3 h (2) · 1 recovery
// not completed yet"; with none completed, "—" for the band and the median,
// "— · 1 recovery not completed yet"; "No failed deployments" with
// neither. A run of failures is one recovery, counted as one episode
// however many deployments failed in it (decision #35).
func (r Recovery) Cell() string {
	if r.Unrecovered == 0 && r.Recoveries == 0 {
		return "No failed deployments"
	}
	completed := "—"
	if r.Recoveries > 0 {
		completed = cell(r.Band, timed(r.Median, r.Recoveries))
	}
	if r.Unrecovered == 0 {
		return completed
	}
	return completed + cellSeparator + counted(r.Unrecovered, "recovery", "recoveries") + " not completed yet"
}

// Cell is the band, the rate in whole percent and the failed changes of the
// deployments, "20% · 14% (1 of 7)"; "No deployments" without any, then the
// failure issues when there are.
func (r ChangeFailRate) Cell() string {
	if r.Deployments > 0 {
		return cell(r.Band, fmt.Sprintf("%d%% (%d of %d)", r.Percent(), r.Failed, r.Deployments))
	}
	if r.FailureIssues > 0 {
		return "No deployments" + cellSeparator + plural(r.FailureIssues, "failure issue")
	}
	return "No deployments"
}

// cell is a band and its measure.
func cell(band fmt.Stringer, measure string) string { return band.String() + cellSeparator + measure }

// timed is a median in short units and the count it is over, "3 h (2)".
func timed(median time.Duration, count int) string {
	return fmt.Sprintf("%s (%d)", shortDuration(median), count)
}
