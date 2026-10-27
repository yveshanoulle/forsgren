package page

import (
	"strconv"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// The Week page (forsgren#531, decisions #532 A, #533 A, #534 A; forsgren#540,
// decision #541): one table with a row per project and per label, service
// and rule, the commits and deployments of the DORA window as a Total and as
// the share on each weekday, Monday first, UTC; or one line that says why there is none.

// WeekPage is the name of the Week page, week.html (forsgren#531).
const WeekPage = "week"

// weekTitle is the Week page's title and h1.
const weekTitle = "Week"

// minuteLayout is a UTC minute as the footer and the Week page write it.
const minuteLayout = "2006-01-02 15:04"

// weekGroups are the column groups of the table after Project: Total, then
// the weekdays in full, Monday first (forsgren#540, decision #541).
var weekGroups = []string{"Total", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"}

// weekDays is the number of weekdays among the groups.
const weekDays = 7

// WeekGroup is a column group of the header: its name, and the labels of its
// Commits and Deployments headers for a screen reader.
type WeekGroup struct{ Name, CommitsLabel, DeploymentsLabel string }

// WeekTitle is weekTitle, for the templates that name the Week page.
func (d Data) WeekTitle() string { return weekTitle }

// WeekGroups are the column groups of the table, Total first.
func (d Data) WeekGroups() []WeekGroup {
	groups := make([]WeekGroup, len(weekGroups))
	for i, name := range weekGroups {
		groups[i] = WeekGroup{name, name + " commits", name + " deployments"}
	}
	return groups
}

// WeekWindow is the sentence above the table: the DORA window in days and
// its first and last minute in UTC, and that every weekday of it counts, not one
// calendar week.
func (d Data) WeekWindow() string {
	return "The last " + strconv.Itoa(d.Window()) + " days, from " + d.Week.Start.Format(minuteLayout) + " to " +
		d.Week.End.Format(minuteLayout) + ", every weekday of that window counted (UTC)."
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

// WeekCell is a figure cell: its text and its class.
type WeekCell struct{ Text, Class string }

// commitsClass is the class of the row's commit cells: num, except for a
// row Per repository, whose commit cells hold an en dash.
func (r WeekRow) commitsClass() string {
	if r.PerRepository {
		return ""
	}
	return "num"
}

// Cells are the cells after the row header: the
// Total's Commits and Deployments, then Commits and Deployments of each weekday,
// Monday first.
func (r WeekRow) Cells() []WeekCell {
	cells := []WeekCell{{r.CommitsTotalCell(), r.commitsClass()}, {r.DeploymentsTotalCell(), "num"}}
	for day := range weekDays {
		cells = append(cells, WeekCell{r.CommitsShareCell(day), r.commitsClass()},
			WeekCell{r.DeploymentsShareCell(day), "num"})
	}
	return cells
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
