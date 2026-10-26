package page

import (
	"strconv"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// The TBD page (forsgren#253): one table with a row per project, in column
// groups under two-level headers (forsgren#397, step 5, Yves's ruling on
// #401): volume, shares of the commits, time to main per commit, commits per
// push, time to deploy per commit and commits per deployment, then the
// PR Lead Time (forsgren#256), the Mainline Interval and the Developers count
// (forsgren#273); or one line that says why there is none. The key tbd_figures
// (forsgren#423) chooses the figures of each measure: the median alone, one
// column each and one header row (the default), or the mean, the median and the
// 90th percentile under two-level headers.

// tbdTitle is the TBD page's title, its h1 and the legend's heading for it,
// as Yves wrote it (forsgren#271): the name alone since the page left beta
// (forsgren#409); the History page keeps its beta marker (betaMarker).
const tbdTitle = "Trunk-based development [TBD]"

// pullsUncollectedCell is the Mainline Lead Time cell while data/pulls.csv
// is absent: no collect has stored pull requests yet (forsgren#256, step 2).
const pullsUncollectedCell = "No pull requests have been collected yet"

// TbdTitle is tbdTitle, for the templates that name the TBD page.
func (d Data) TbdTitle() string { return tbdTitle }

// TbdMessage is the one line the TBD page shows in place of its table: there
// are no projects, or no Mainline Interval has been read.
func (d Data) TbdMessage() string {
	if d.NoProjects {
		return "No projects are listed yet, so there is no Mainline Interval to show."
	}
	return "No commits have been collected yet, so there is no Mainline Interval to show."
}

// TbdRow is one row of the TBD page (forsgren#397, step 5; forsgren#422, step
// 4): a project's total or a label's or service's row, with the measures
// metrics.TbdRows gives it: the volume, shares and push and deployment
// measures, the Mainline Lead Time (forsgren#256, step 2; the pull requests
// column alone), the Mainline Interval and the Developers count
// (forsgren#273). Its NoData rule and its NotesName are the metrics row's.
type TbdRow struct {
	metrics.TbdRow
	// pullsUncollected is Data.PullsUncollected.
	pullsUncollected bool
	// window is Data.Window, the DORA window in days.
	window int
}

// IsLabel says whether the row is a label's or a service's, under its
// project's total.
func (r TbdRow) IsLabel() bool { return r.Level == metrics.LabelRow }

// NoDataSentence is the one cell of a row without data, naming the window of
// the config's dora_days: of the project, or of the service for a service row
// (forsgren#422, step 4, decision #451).
func (r TbdRow) NoDataSentence() string {
	kind := "project"
	if r.Service {
		kind = "service"
	}
	return "currently no data for this " + kind + " in the last " + strconv.Itoa(r.window) + " days"
}

// CommitsCell and PushesCell are the commits and pushes of the push groups, a
// dash on a service row.
func (r TbdRow) CommitsCell() string { return r.pushed(r.Push.CommitsCell()) }

// PushesCell is the pushes of the window, a dash on a service row.
func (r TbdRow) PushesCell() string { return r.pushed(r.Push.PushesCell()) }

// pushed is cell, a dash on a service row.
func (r TbdRow) pushed(cell string) string {
	if r.PushAbsent {
		return noCell
	}
	return cell
}

// noCell is the dash of a cell without a value.
const noCell = "-"

// The columns of the table after the project: the median alone, or the mean,
// the median and the 90th percentile (the shares have four, the developers one).
const (
	tbdColumnsMedian = 14
	tbdColumnsAll    = 26
)

// TbdColumnsAfterProject is how many columns the row of a project without data
// spans: those after the project's own.
func (d Data) TbdColumnsAfterProject() int {
	if d.TbdAll() {
		return tbdColumnsAll
	}
	return tbdColumnsMedian
}

// LeadState is the sentence in place of the row's pull requests cells, in the
// PR Lead Time group, or empty when the group has its figures: "Pull requests
// not readable" for a project a refused read makes not readable (forsgren#337,
// step 2), else pullsUncollectedCell while the pull requests have not been
// collected (forsgren#256, step 2).
func (r TbdRow) LeadState() string {
	switch {
	case r.PushAbsent:
		return ""
	case r.Lead.NotReadable:
		return r.Lead.State()
	case r.pullsUncollected:
		return pullsUncollectedCell
	}
	return ""
}

// TbdAll says whether the TBD table shows the mean, the median and the 90th
// percentile of each measure (tbd_figures: all) or the median alone, the
// default (forsgren#423).
func (d Data) TbdAll() bool { return d.TbdFigures == config.TbdFiguresAll }

// TbdRows are the rows of the TBD table, in the order of Data.TbdMetrics: each
// project's total, then its label rows.
func (d Data) TbdRows() []TbdRow {
	rows := make([]TbdRow, len(d.TbdMetrics))
	for i, m := range d.TbdMetrics {
		rows[i] = TbdRow{TbdRow: withoutAbsent(m), pullsUncollected: d.PullsUncollected, window: d.Window()}
	}
	return rows
}

// withoutAbsent is the row without the measures it says are absent
// (IntervalAbsent, PushAbsent), so that its cells show a dash because the row
// says so, never because a measure happens to be empty.
func withoutAbsent(m metrics.TbdRow) metrics.TbdRow {
	if m.IntervalAbsent {
		m.Interval = metrics.MainlineInterval{}
	}
	if m.PushAbsent {
		m.Lead, m.Push = metrics.MainlineLeadTime{}, metrics.PushMeasures{}
	}
	return m
}
