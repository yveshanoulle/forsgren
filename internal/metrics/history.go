package metrics

// The history page's periods (forsgren#68): the columns of its tables.

import (
	"fmt"
	"slices"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// RollingDays is the length of the newest column and the days every period
// is banded as, DORA's 180 (forsgren#68).
const RollingDays = 180

// rollingLabel is the label of the newest column.
const rollingLabel = "Last 6 months"

// Period is one column of the history page: the span [Start, End) of UTC
// time it counts, and its label.
type Period struct {
	Label      string
	Start, End time.Time
	// Rolling says whether it is the newest column, the last 180 days up to
	// the render time, rather than a calendar half-year.
	Rolling bool
}

// Periods are the history page's columns at the render time now, oldest first
// (forsgren#68): the calendar half-years (Jan-Jun, Jul-Dec, UTC) that are
// complete and start within historyDays, at most config.MaxHistoryDays, then
// the rolling last 180 days up to now. There are none when historyDays is
// under 180, as the rolling column would not be fully read.
func Periods(now time.Time, historyDays int) []Period {
	if historyDays < RollingDays {
		return nil
	}
	earliest := now.Add(-time.Duration(min(historyDays, config.MaxHistoryDays)) * day)
	var periods []Period
	for start := halfYearBefore(currentHalfYearStart(now)); !start.Before(earliest); start = halfYearBefore(start) {
		periods = append(periods, Period{Label: halfYearLabel(start), Start: start, End: start.AddDate(0, 6, 0)})
	}
	slices.Reverse(periods)
	return append(periods, Period{Label: rollingLabel, Start: now.Add(-RollingDays * day), End: now, Rolling: true})
}

// currentHalfYearStart is the first day of the half-year now is in: January 1
// or July 1, UTC.
func currentHalfYearStart(now time.Time) time.Time {
	now = now.UTC()
	month := time.January
	if now.Month() >= time.July {
		month = time.July
	}
	return time.Date(now.Year(), month, 1, 0, 0, 0, 0, time.UTC)
}

// halfYearBefore is the start of the half-year before the one that starts at
// start.
func halfYearBefore(start time.Time) time.Time { return start.AddDate(0, -6, 0) }

// halfYearLabel is "2025 H2" for the half-year starting at start.
func halfYearLabel(start time.Time) string {
	return fmt.Sprintf("%d H%d", start.Year(), (int(start.Month())-1)/6+1)
}

// PeriodRows are the history page's rows for one period (forsgren#68): the
// table's rows, as Rows gives them, counted over the period's own days ending
// at its end, from what was created before it: the start is counted, the end
// is not (the rolling column's end, now, is), and nothing later is seen.
func PeriodRows(projects []config.Project, data Data, p Period) []Row {
	data.DoraDays, data.BandDays, data.UnreadBefore = int(p.End.Sub(p.Start)/day), RollingDays, p.Start
	data.Records = seen(p, data.Records, func(r history.Record) time.Time { return r.CreatedAt })
	data.Commits = seen(p, data.Commits, func(c history.Commit) time.Time { return c.DeployedAt })
	data.Failures = seen(p, data.Failures, func(f history.Failure) time.Time { return f.OpenedAt })
	return Rows(projects, data, p.End)
}

// seen is a copy of the items that came before the period was over, each at
// the time when gives.
func seen[T any](p Period, items []T, when func(T) time.Time) []T {
	return slices.DeleteFunc(slices.Clone(items), func(item T) bool { return p.over(when(item)) })
}

// over says whether something at at came after the period: at its end or
// later for a calendar half-year, which ends before its End, and later than
// now for the rolling column, which ends at now, both ends included as for the
// table.
func (p Period) over(at time.Time) bool {
	if p.Rolling {
		return at.After(p.End)
	}
	return !at.Before(p.End)
}

// Column is one column of the history page: a period and the rows counted
// over it (forsgren#68).
type Column struct {
	Period Period
	Rows   []Row
}

// History are the history page's columns at the render time now, oldest
// first: the Periods for historyDays, each with its PeriodRows, less a period
// no row has data for, that is where every row is unread or has no deployment
// yet (forsgren#68).
func History(projects []config.Project, data Data, now time.Time, historyDays int) []Column {
	var columns []Column
	for _, period := range Periods(now, historyDays) {
		rows := PeriodRows(projects, data, period)
		if slices.ContainsFunc(rows, Row.HasData) {
			columns = append(columns, Column{Period: period, Rows: rows})
		}
	}
	return columns
}

// HasData says whether the row is read and has a deployment, so the history
// page shows its numbers; a row without them shows a dash in every cell.
func (r Row) HasData() bool { return !r.Unread && r.HasDeployments() }

// HalfYearOf is the calendar half-year (UTC) that holds at: its label, its
// first day and the day after it ends (forsgren#198).
func HalfYearOf(at time.Time) (label string, start, next time.Time) {
	start = currentHalfYearStart(at)
	return halfYearLabel(start), start, start.AddDate(0, 6, 0)
}

// FirstDeployment is the creation time of the oldest successful deployment of
// the repositories of projects in data, false when there is none (forsgren#198).
func FirstDeployment(projects []config.Project, data Data) (time.Time, bool) {
	index := indexOf(projects)
	var first time.Time
	for _, r := range data.Records {
		if _, ok := index.of(r.Repository); ok && r.State == history.StateSuccess {
			first = earlier(first, r.CreatedAt)
		}
	}
	return first, !first.IsZero()
}
