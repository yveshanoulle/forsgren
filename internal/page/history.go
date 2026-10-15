package page

// The history page (forsgren#68): the DORA metrics of every period in one
// table, a group of rows per measure, a row per table row in it and a column
// per period, oldest first.

import "github.com/yveshanoulle/forsgren/internal/metrics"

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

// HistoryRow is a row of a history table: the row's heading and its cell per
// period.
type HistoryRow struct {
	Row
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
		sections[m] = HistorySection{Title: measure, Span: len(d.History) + 1, Rows: d.historyRows(headings, m)}
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
		for c, column := range d.History {
			rows[r].Cells[c] = historyCells(Row{Row: column.Rows[r]})[m]
		}
	}
	return rows
}

// historyCells are the row's cells in the order of historyMeasures: Overall
// Performance, then each metric as number and score. A row that is unread or
// has no deployment yet has none: a dash each.
func historyCells(r Row) []string {
	if r.Unread || !r.HasDeployments() {
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
