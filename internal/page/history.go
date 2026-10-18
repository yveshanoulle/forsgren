package page

// The history page (forsgren#68): the DORA metrics of every period in one
// table, a block per project (forsgren#211), a row per measure in it for the
// project and for each label, and a column per period, oldest first.

import (
	"fmt"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// betaMarker is what marks the History page while it is in beta (forsgren#198):
// its title, its heading and the legend's section heading. Leaving beta is
// setting it to the empty string.
const betaMarker = " (beta)"

// historyBeta is betaMarker, for the templates that name the History page.
func historyBeta() string { return betaMarker }

// historyMeasures are the measures of each project's block in order: the
// Overall Performance first, then the five metrics in the table's order.
var historyMeasures = []string{
	"Overall Performance",
	"Deployment frequency",
	"Lead time for changes",
	"Failed deployment recovery time",
	"Change fail rate",
	"Deployment rework rate",
}

// HistoryGroup is one project's block of the history page's table (forsgren#211):
// the project's name, Span columns wide with the row headings, then a row per
// measure for the project's total and for each of its labels.
type HistoryGroup struct {
	Title string
	Span  int
	Rows  []HistoryRow
}

// HistoryRow is a row of a history table: one measure of one table row, its
// heading, its chart and its cell per period.
type HistoryRow struct {
	Row
	Measure string
	Chart   *HistoryChart
	Cells   []string
}

// HistoryGroups are the blocks of the history page's table, one per project in
// the table page's order, none when there are no columns.
func (d Data) HistoryGroups() []HistoryGroup {
	if len(d.History) == 0 {
		return nil
	}
	var groups []HistoryGroup
	for r, heading := range Table(d.History[0].Rows) {
		if heading.Level == metrics.ProjectRow || len(groups) == 0 {
			groups = append(groups, HistoryGroup{Title: heading.Name, Span: d.historySpan()})
		}
		last := &groups[len(groups)-1]
		last.Rows = append(last.Rows, d.historyRows(heading, r)...)
	}
	return groups
}

// HistoryOnePeriod says whether the table has a single period column, which
// leaves out the Trend column: a trend needs two periods (forsgren#198).
func (d Data) HistoryOnePeriod() bool { return len(d.History) == 1 }

// historySpan is how many columns a group header spans: the row headings,
// the periods, and the Trend column when it is shown.
func (d Data) historySpan() int {
	span := 1 + len(d.History)
	if !d.HistoryOnePeriod() {
		span++
	}
	return span
}

// HistoryPeriods are the headers of the history page's period columns, oldest
// first.
func (d Data) HistoryPeriods() []string {
	periods := make([]string, len(d.History))
	for c, column := range d.History {
		periods[c] = periodHeader(column.Period)
	}
	return periods
}

// historyRows are the rows of one table row, the heading at index r: a row per
// measure, each with its cell in every column.
func (d Data) historyRows(heading Row, r int) []HistoryRow {
	rows := make([]HistoryRow, len(historyMeasures))
	for m, measure := range historyMeasures {
		rows[m] = HistoryRow{Row: heading, Measure: measure, Cells: make([]string, len(d.History))}
		scores := make([]score, len(d.History))
		for c, column := range d.History {
			row := Row{Row: column.Rows[r]}
			rows[m].Cells[c] = historyCells(row)[m]
			scores[c] = chartScore(row, m)
		}
		rows[m].Chart = historyChart(chartTitle(m, heading.Heading, d.History), scores)
	}
	return rows
}

// historyCells are the row's cells in the order of historyMeasures: Overall
// Performance, then each metric as number and score. A row without data, unread
// or with no deployment yet, has none: a dash each.
func historyCells(r Row) []string {
	if !r.HasData() {
		cells := make([]string, len(historyMeasures))
		for i := range cells {
			cells[i] = noScore
		}
		return cells
	}
	return append([]string{r.OverallCell()}, r.NumberScoreCells()...)
}

// periodHeader is the header of a period's column: its label, and for the
// rolling one the day it runs to.
func periodHeader(p metrics.Period) string {
	if p.Rolling {
		return p.Label + " to " + p.End.Format(dateLayout)
	}
	return p.Label
}

// HistoryEdges are the band edges of the history page's 180 days
// (forsgren#68).
func (d Data) HistoryEdges() metrics.Edges { return metrics.EdgesOf(metrics.RollingDays) }

// HistoryOnDemandFrom is the lowest count over the 180 days of a history
// period that is on demand for the working day (forsgren#68).
func (d Data) HistoryOnDemandFrom() int {
	return metrics.OnDemandFrom(d.WorkingHours, metrics.RollingDays)
}

// HistoryMessage is the one line the history page shows in place of its table
// (forsgren#68): there are no projects, history_days is too short for the
// last 6 months, or there is nothing to show yet.
func (d Data) HistoryMessage() string {
	switch {
	case d.NoProjects:
		return "No projects are listed yet, so there is no history to show."
	case d.HistoryDays > 0 && d.HistoryDays < metrics.RollingDays:
		return fmt.Sprintf("history_days is %d, too short for the last 6 months: set history_days to at least %d "+
			"in forsgren.config.yml, and this page fills over the next runs.", d.HistoryDays, metrics.RollingDays)
	}
	return "No history to show yet: the periods fill as the history is collected, over the next runs."
}
