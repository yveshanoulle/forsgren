package page

import (
	"strconv"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// The Week page (forsgren#531, decisions #532 A, #533 A, #534 A): one table
// with a row per project and per label, service and rule, the commits and
// deployments of the DORA window per weekday, Monday first, UTC, and the
// weekend share of the commits; or one line that says why there is none.

// WeekPage is the name of the Week page, week.html (forsgren#531).
const WeekPage = "week"

// weekTitle is the Week page's title and h1.
const weekTitle = "Week"

// weekDays are the weekday column headers, Monday first.
var weekDays = []string{"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"}

// WeekTitle is weekTitle, for the templates that name the Week page.
func (d Data) WeekTitle() string { return weekTitle }

// WeekDays are the weekday headers of the table.
func (d Data) WeekDays() []string { return weekDays }

// WeekWindow is the sentence above the table: the DORA window in days and
// its first and last day, and that every weekday of it counts, not one
// calendar week.
func (d Data) WeekWindow() string {
	return "The last " + strconv.Itoa(d.Window()) + " days, from " + d.Week.Start.Format(dateLayout) + " to " +
		d.Week.End.Format(dateLayout) + ", every weekday of that window counted (UTC)."
}

// WeekMessage is the one line the Week page shows in place of its table.
func (d Data) WeekMessage() string {
	if d.NoProjects {
		return "No projects are listed yet, so there is no week to show."
	}
	return "No commits or deployments have been collected yet, so there is no week to show."
}

// WeekRow is one row of the Week page: the metrics row with its cells.
type WeekRow struct{ metrics.WeekRow }

// IsLabel says whether the row is a label's, service's or rule's, under its
// project's total.
func (r WeekRow) IsLabel() bool { return r.Level == metrics.LabelRow }

// Cells are the seven day cells, Monday first.
func (r WeekRow) Cells() []string {
	cells := make([]string, len(weekDays))
	for day := range cells {
		cells[day] = r.DayCell(day)
	}
	return cells
}

// Class is the class of the row's figure cells: num, except for a row Per
// repository, whose cells hold words.
func (r WeekRow) Class() string {
	if r.PerRepository {
		return ""
	}
	return "num"
}

// WeekRows are the rows of the Week table, in the order of Data.Week: each
// project's total, then its label rows, which sub_rows: false leaves out
// (forsgren#482).
func (d Data) WeekRows() []WeekRow {
	var rows []WeekRow
	for _, m := range d.Week.Rows {
		if !d.leavesOut(m.Level) {
			rows = append(rows, WeekRow{m})
		}
	}
	return rows
}
