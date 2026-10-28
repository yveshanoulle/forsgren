package page

import "github.com/yveshanoulle/forsgren/internal/metrics"

// The Week page (forsgren#531, decisions #532 A, #533 A, #534 A; forsgren#540,
// decision #541): one table with a row per project and per label, service
// and rule, the deployments, failed deployments and fail rate of the DORA
// window as a Total and per weekday, Monday first, UTC, the commits too with
// week_commits: true (forsgren#548, #555); or one line that says why there is none.

// WeekPage is the name of the Week page, week.html (forsgren#531).
const WeekPage = "week"

// weekTitle is the Week page's title and h1.
const weekTitle = "Week"

// weekGroups are the column groups of the table after Project: Total, then
// the weekdays in full, Monday first (forsgren#540, decision #541).
var weekGroups = []string{"Total", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"}

// weekDays is the number of weekdays among the groups.
const weekDays = 7

// WeekGroup is a column group of the header: its name, the labels of its
// Commits, Deployments, Failed and Fail rate headers for a screen reader, and
// the visible text of its deployments header: Deployments under Total,
// Deploys under a weekday (forsgren#552), the label keeping the full word.
type WeekGroup struct {
	Name, CommitsLabel, DeploymentsLabel, FailedLabel, FailRateLabel string
	DeploymentsHeader                                                string
}

// weekdayDeploymentsHeader is the shorter header of a weekday's deployments,
// which saves width; totalDeploymentsHeader is the Total group's.
const (
	weekdayDeploymentsHeader = "Deploys"
	totalDeploymentsHeader   = "Deployments"
)

// WeekTitle is weekTitle, for the templates that name the Week page.
func (d Data) WeekTitle() string { return weekTitle }

// WeekGroups are the column groups of the table, Total first.
func (d Data) WeekGroups() []WeekGroup {
	groups := make([]WeekGroup, len(weekGroups))
	for i, name := range weekGroups {
		groups[i] = WeekGroup{name, name + " commits", name + " deployments",
			name + " failed deployments", name + " fail rate", weekdayDeploymentsHeader}
	}
	groups[0].DeploymentsHeader = totalDeploymentsHeader
	return groups
}

// WeekMessage is the one line the Week page shows in place of its table.
func (d Data) WeekMessage() string {
	if d.NoProjects {
		return "No projects are listed yet, so there is no week to show."
	}
	return "No commits or deployments have been collected yet, so there is no week to show."
}

// WeekColumns is the number of columns of each header group: Deployments,
// Failed and Fail rate, and Commits too with week_commits: true (forsgren#548,
// decision #549 A).
func (d Data) WeekColumns() int {
	if d.WeekCommits {
		return 4
	}
	return 3
}

// WeekRow is one row of the Week page: the metrics row with its cells, and
// whether the page shows the Commits cells.
type WeekRow struct {
	metrics.WeekRow
	commits bool
}

// IsLabel says whether the row is a label's, service's or rule's, under its
// project's total.
func (r WeekRow) IsLabel() bool { return r.Level == metrics.LabelRow }

// WeekCell is a figure cell: its text and its class. Highest marks the
// weekday cell of Failed or Fail rate with the highest value of its row
// (forsgren#545): the class highest, red, and a visually hidden word.
type WeekCell struct {
	Text, Class string
	Highest     bool
}

// CellClass is the cell's class attribute value: its class, with highest
// after it when the cell is marked.
func (c WeekCell) CellClass() string {
	if c.Highest {
		return "num highest"
	}
	return c.Class
}

// commitsClass is the class of the row's commit cells: num, except for a
// row Per repository, whose commit cells hold an en dash.
func (r WeekRow) commitsClass() string {
	if r.PerRepository {
		return ""
	}
	return "num"
}

// Cells are the cells after the row header: the Total's Commits (with
// week_commits: true), Deployments, Failed and Fail rate, then those of each
// weekday, Monday first (forsgren#545, decision #546; forsgren#548).
func (r WeekRow) Cells() []WeekCell {
	cells := r.commitsCell(WeekCell{r.CommitsTotalCell(), r.commitsClass(), false}, nil)
	cells = append(cells, WeekCell{r.DeploymentsTotalCell(), "num", false},
		WeekCell{r.FailedTotalCell(), "num", false}, WeekCell{r.FailRateTotalCell(), "num", false})
	for day := range weekDays {
		cells = r.commitsCell(WeekCell{r.CommitsShareCell(day), r.commitsClass(), false}, cells)
		cells = append(cells, WeekCell{r.DeploymentsShareCell(day), "num", false},
			WeekCell{r.FailedShareCell(day), "num", r.FailedHighest(day)},
			WeekCell{r.FailRateCell(day), "num", r.FailRateHighest(day)})
	}
	return cells
}

// commitsCell is cells with the Commits cell added when the page shows them.
func (r WeekRow) commitsCell(cell WeekCell, cells []WeekCell) []WeekCell {
	if r.commits {
		return append(cells, cell)
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
			rows = append(rows, WeekRow{m, d.WeekCommits})
		}
	}
	return rows
}

// WeekTotal is the Total row, the first row under the column headers
// (Yves's reply on #553): the sum of every project
// row, with the cells of a project row (forsgren#552, decision #553 A).
func (d Data) WeekTotal() WeekRow { return WeekRow{d.Week.Total(), d.WeekCommits} }

// WeekHasTotal says whether the table has its Total row: only with two
// project rows or more, label, service and rule rows not counted, since one
// project's Total would only repeat its row (forsgren#552, Yves's ruling).
func (d Data) WeekHasTotal() bool {
	projects := 0
	for _, row := range d.Week.Rows {
		if row.Level == metrics.ProjectRow {
			projects++
		}
	}
	return projects >= 2
}
