package page

// The history page (forsgren#68): the DORA metrics of every period in one
// table, a group of rows per measure, a row per table row in it and a column
// per period, oldest first.

import (
	"fmt"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// historyMeasures are the history page's row groups in order: the Overall
// Performance first, then the five metrics in the table's order.
var historyMeasures = []string{
	"Overall Performance",
	"Deployment frequency",
	"Lead time for changes",
	"Failed deployment recovery time",
	"Change fail rate",
	"Deployment rework rate",
}

// HistorySection is one group of rows of the history page's table: a measure
// and a row per table row, Span columns wide with the row headings.
type HistorySection struct {
	Title string
	Span  int
	Rows  []HistoryRow
}

// HistoryRow is a row of a history table: the row's heading, its chart and its
// cell per period.
type HistoryRow struct {
	Row
	Chart *HistoryChart
	Cells []string
}

// HistorySections are the tables of the history page, one per measure, none
// when there are no columns.
func (d Data) HistorySections() []HistorySection {
	if len(d.History) == 0 {
		return nil
	}
	headings := Table(d.History[0].Rows)
	sections := make([]HistorySection, len(historyMeasures))
	for m, measure := range historyMeasures {
		sections[m] = HistorySection{Title: measure, Span: len(d.History) + 2, Rows: d.historyRows(headings, m)}
	}
	return sections
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

// historyRows are the rows of the section of measure m: the headings, each
// with its cell of m in every column.
func (d Data) historyRows(headings []Row, m int) []HistoryRow {
	rows := make([]HistoryRow, len(headings))
	for r, heading := range headings {
		rows[r] = HistoryRow{Row: heading, Cells: make([]string, len(d.History))}
		scores := make([]score, len(d.History))
		for c, column := range d.History {
			row := Row{Row: column.Rows[r]}
			rows[r].Cells[c] = historyCells(row)[m]
			scores[c] = chartScore(row, m)
		}
		rows[r].Chart = historyChart(chartTitle(m, heading.Heading, d.History), scores)
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
		return p.Label + " to " + p.End.Format("2006-01-02")
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
