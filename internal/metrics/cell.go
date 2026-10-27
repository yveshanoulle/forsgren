package metrics

// The cells of the page's table (forsgren#38): each metric in short, its
// DORA band first, then the number that decided it and the count it is
// over, "Less than one day · 2 h 7 min (48)". The legend page (legend.html)
// says what each counts and over which window.

import (
	"fmt"
	"time"
)

// cellSeparator separates the parts of a cell.
const cellSeparator = " · "

// Cell is the band and the count that decided it, the DORA window's or,
// with none in it, the last 180 days': "Between once per day and once per
// week · 7"; a row whose deployments all failed shows its band of none,
// "Less than once per six months · 0" (decision #35).
func (f Frequency) Cell() string {
	return cell(f.Band, GroupDigits(f.shown().deployments))
}

// WeekendCell is how many of the deployments Cell counts were created on a
// Saturday or a Sunday, UTC, over the same window (forsgren#124).
func (f Frequency) WeekendCell() string { return GroupDigits(f.shown().weekends) }

// windowCounts are the successful deployments over one window and the
// weekend ones among them, the two numbers a view shows side by side
// (forsgren#124).
type windowCounts struct{ deployments, weekends int }

// shown are the counts of the window the frequency cell shows: the DORA
// window's, or, with none in it, the last 180 days'.
func (f Frequency) shown() windowCounts {
	if f.InWindow == 0 {
		return windowCounts{f.Last180, f.Weekend180}
	}
	return f.ofWindow()
}

// ofWindow are the counts of the DORA window, the window the numbers view
// shows (forsgren#178).
func (f Frequency) ofWindow() windowCounts { return windowCounts{f.InWindow, f.WeekendInWindow} }

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
		return cell(r.Band, fmt.Sprintf("%d%% (%s of %s)", r.Percent(), GroupDigits(r.Failed), GroupDigits(r.Deployments)))
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
	return fmt.Sprintf("%s (%s)", shortDuration(median), GroupDigits(count))
}
