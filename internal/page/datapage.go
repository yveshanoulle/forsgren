package page

import (
	"time"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// The Data page (forsgren#579, step 2): one table with a row per project and
// per label, service and rule, the first time forsgren stored data of each
// kind, a date after Report Start marked; under it, which pages use each kind.

// DataPage is the name of the Data page, data.html (forsgren#579).
const DataPage = "data"

// dataTitle is the Data page's title and h1.
const dataTitle = "Data"

// dataKind is a kind of stored data: its column header and the pages that use it.
type dataKind struct{ Name, UsedBy string }

// dataKinds are the Data page's columns after Project, in the order of the
// cells of DataRow.Cells, and the list under the table.
var dataKinds = []dataKind{
	{"Deployments", "the five DORA metrics on the standard, numbers and scoring views, the History and the Week page"},
	{"Commits", "lead time for changes and the TBD Mainline Interval and Time to deploy"},
	{"Pushes", "the TBD Time to main, Commits per push and shares, and the commits of the Week page"},
	{"Merged pull requests", "the TBD PR Lead Time and Bot PR Lead Time"},
	{"Issues", "the Issues and Daily pages"},
}

// noData is the cell of a kind with nothing stored.
const noData = "-"

// DataKinds are the kinds of stored data, for the template.
func (d Data) DataKinds() []dataKind { return dataKinds }

// DataTitle is dataTitle, for the templates that name the Data page.
func (d Data) DataTitle() string { return dataTitle }

// DataMessage is the one line the Data page shows in place of its table.
func (d Data) DataMessage() string {
	if d.NoProjects {
		return "No projects are listed yet, so there is no data to show."
	}
	return "No data has been collected yet, so there is no first date to show."
}

// DataRow is one row of the Data page: the metrics row and Report Start.
type DataRow struct {
	metrics.DataRow
	start time.Time
}

// IsLabel says whether the row is a label's, service's or rule's, under its
// project's total.
func (r DataRow) IsLabel() bool { return r.Level == metrics.LabelRow }

// DataCell is one cell of a kind: its text, and Late when the date is after
// Report Start.
type DataCell struct {
	Text string
	Late bool
}

// Cells are the row's cells, one per kind of dataKinds.
func (r DataRow) Cells() []DataCell {
	starts := []metrics.DataStart{r.Deployments, r.Commits, r.Pushes, r.Pulls, r.Issues}
	cells := make([]DataCell, len(starts))
	for i, s := range starts {
		cells[i] = dataCell(s, r.start)
	}
	return cells
}

// dataCell is the cell of s: Per repository, a dash for nothing stored, or
// the date, late when after start.
func dataCell(s metrics.DataStart, start time.Time) DataCell {
	switch {
	case s.PerRepository:
		return DataCell{Text: perRepositorySentence}
	case !s.Stored():
		return DataCell{Text: noData}
	}
	return DataCell{Text: s.At.UTC().Format(dateLayout), Late: s.Late(start)}
}

// DataRows are the rows of the Data table, in the order of Data.DataStarts:
// each project's total, then its label rows, which sub_rows: false leaves out.
func (d Data) DataRows() []DataRow {
	var rows []DataRow
	for _, m := range d.DataStarts.Rows {
		if !d.leavesOut(m.Level) {
			rows = append(rows, DataRow{m, d.DataStarts.Start})
		}
	}
	return rows
}
