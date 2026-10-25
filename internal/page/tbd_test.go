package page

import (
	"bytes"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// tbdData is the TBD page's data: Acme Shop with 4 commits and a deviation,
// Acme Tools with 2 commits, so a mean and no deviation, and Acme Docs with
// no commit; their Mainline Lead Times (tbdLeads), their Developers, and the
// push and deployment groups of forsgren#397, step 5: Acme Shop with every
// figure, Acme Tools with a mean only, Acme Docs with its push read refused
// and Acme Web with no push collected yet. Acme Shop has half of its commits
// timed by author date, so a plain note; Acme Web has more than half, so the
// cell says so (forsgren#345, step 3).
func tbdData() Data {
	return tbdDataWith(tbdLeads())
}

// tbdLeads are the Mainline Lead Times of tbdData (forsgren#256, step 2):
// Acme Shop's 5 pull requests with a median, Acme Tools' one cut pull
// request, no human one for Acme Docs but 2 of bots, and Acme Web's 12 with
// one timed by its created time, next to 3 of bots and 1 of unknown author
// (forsgren#345, step 2).
func tbdLeads() []metrics.MainlineLeadTime {
	return []metrics.MainlineLeadTime{
		{Project: "Acme Shop", PullRequests: 5, Mean: 3 * time.Hour, Median: 2 * time.Hour},
		{Project: "Acme Tools", PullRequests: 1, Mean: 30 * time.Hour, Cut: 1},
		{Project: "Acme Docs", Bots: 2},
		{Project: "Acme Web", PullRequests: 12, Mean: 20 * time.Hour, Median: 10 * time.Hour, P90: 30 * time.Hour,
			CreatedStandsIn: 1, Bots: 3},
	}
}

// tbdDataWith is tbdData with the Mainline Lead Times leads.
func tbdDataWith(leads []metrics.MainlineLeadTime) Data {
	data := calculated()
	data.Mainline = []metrics.MainlineInterval{
		{Project: "Acme Shop", Commits: 4, Gaps: 3, Mean: 2 * time.Hour, Median: 2 * time.Hour, ByAuthorDate: 2},
		{Project: "Acme Tools", Commits: 2, Gaps: 1, Mean: 2 * time.Hour},
		{Project: "Acme Docs"},
		{Project: "Acme Web", Commits: 13, Gaps: 12, Mean: 24 * time.Minute, Median: 5 * time.Minute, P90: time.Hour,
			ByAuthorDate: 7},
	}
	data.Developers = []metrics.Developers{
		{Project: "Acme Shop", Count: 3, Commits: 4},
		{Project: "Acme Tools", Count: 1, Commits: 2},
		{Project: "Acme Docs", Count: 1, Commits: 1},
		{Project: "Acme Web", Count: 12, Commits: 20},
	}
	data.MainlineLead = leads
	data.PushMeasures = tbdPushes()
	data.DeployMeasures = tbdDeploys()
	data.DeploymentVolumes = []metrics.DeploymentVolume{
		{Project: "Acme Shop", Count: 85}, {Project: "Acme Tools", Count: 7},
		{Project: "Acme Docs", Count: 2}, {Project: "Acme Web", Count: 1},
	}
	return data
}

// tbdPushes are the push measures of tbdData's projects.
func tbdPushes() []metrics.PushMeasures {
	return []metrics.PushMeasures{
		{Project: "Acme Shop", Pushes: 20, Commits: 40, PullRequests: 10, Direct: 30, UnknownAuthors: 4, Bots: 2,
			TimeToMain: metrics.DurationSpread{Count: 40, Mean: time.Hour, Median: 30 * time.Minute, P90: 3 * time.Hour},
			PerPush:    metrics.CountSpread{Count: 20, Mean: 2, Median: 1.5, P90: 6}},
		{Project: "Acme Tools", Pushes: 1, Commits: 1, Direct: 1,
			TimeToMain: metrics.DurationSpread{Count: 1, Mean: 2 * time.Hour},
			PerPush:    metrics.CountSpread{Count: 1, Mean: 1}},
		{Project: "Acme Docs", NotReadable: true},
		{Project: "Acme Web", Uncollected: true},
	}
}

// tbdDeploys are the deployment measures of tbdData's projects: Acme Shop
// with ten deployments, so every figure, Acme Tools with one, Acme Docs with
// two and Acme Web with one.
func tbdDeploys() []metrics.DeployMeasures {
	return []metrics.DeployMeasures{
		{Project: "Acme Shop", Commits: 50, Deployments: 10,
			TimeToDeploy:  metrics.DurationSpread{Count: 50, Mean: 2 * time.Hour, Median: time.Hour, P90: 5 * time.Hour},
			PerDeployment: metrics.CountSpread{Count: 10, Mean: 5, Median: 4.5, P90: 12}},
		{Project: "Acme Tools", Commits: 3, Deployments: 1,
			TimeToDeploy:  metrics.DurationSpread{Count: 3, Mean: time.Hour, Median: time.Hour},
			PerDeployment: metrics.CountSpread{Count: 1, Mean: 3}},
		{Project: "Acme Docs", Commits: 2, Deployments: 2,
			TimeToDeploy:  metrics.DurationSpread{Count: 2, Mean: 30 * time.Minute, Median: 30 * time.Minute},
			PerDeployment: metrics.CountSpread{Count: 2, Mean: 1, Median: 1}},
		{Project: "Acme Web", Commits: 1, Deployments: 1,
			TimeToDeploy:  metrics.DurationSpread{Count: 1, Mean: 10 * time.Minute},
			PerDeployment: metrics.CountSpread{Count: 1, Mean: 2}},
	}
}

// The cells of tbdData's projects, in the two ways the key tbd_figures shows
// them (forsgren#423): [0] with the median only, the default, one cell per
// measure; [1] with all, the mean, the median and the p90 of each. Cells are
// parted by " | "; a cell starting with @N is the push group's state cell,
// N columns wide (forsgren#418; one column wide is a plain cell), one starting
// with {N,M} carries the notes N and M.
//
// tbdTimeCells are the cells around the pull requests cell on its left: time
// to main, then time to deploy. tbdCountCells are the cells on its right:
// volume (commits, pushes, deployments), commits per push, commits per
// deployment and the shares (direct, PR, unknown, bots).
var tbdTimeCells = map[string][2]string{
	"Acme Shop":  {"30 m | 1 h", "1 h | 30 m | 3 h | 2 h | 1 h | 5 h"},
	"Acme Tools": {"- | 1 h", "2 h | - | - | 1 h | 1 h | -"},
	"Acme Docs":  {"@1Push activity not readable | 30 m", "@3Push activity not readable | 30 m | 30 m | -"},
	"Acme Web":   {"@1Pushes not collected yet | -", "@3Pushes not collected yet | 10 m | - | -"},
}

var tbdCountCells = map[string][2]string{
	"Acme Shop": {"40 | 20 | 85 | 1.5 | 4.5 | 75% | 25% | 10% | 5%",
		"40 | 20 | 85 | 2 | 1.5 | 6 | 5 | 4.5 | 12 | 75% | 25% | 10% | 5%"},
	"Acme Tools": {"1 | 1 | 7 | - | - | 100% | 0% | 0% | 0%",
		"1 | 1 | 7 | 1 | - | - | 3 | - | - | 100% | 0% | 0% | 0%"},
	"Acme Docs": {"- | - | 2 | @1Push activity not readable | 1 | @4Push activity not readable",
		"- | - | 2 | @3Push activity not readable | 1 | 1 | - | @4Push activity not readable"},
	"Acme Web": {"- | - | 1 | @1Pushes not collected yet | - | @4Pushes not collected yet",
		"- | - | 1 | @3Pushes not collected yet | 2 | - | - | @4Pushes not collected yet"},
}

// tbdIntervalCells are the Mainline Interval cells of tbdData's projects: Acme
// Shop with half of its commits timed by author date, Acme Web with more than
// half (forsgren#345, step 3), the note on the median cell when only the
// median is shown and on the mean cell with all (forsgren#423).
var tbdIntervalCells = map[string][2]string{
	"Acme Shop":  {"{2}2 h", "{2}2 h | 2 h | -"},
	"Acme Tools": {"-", "2 h | - | -"},
	"Acme Docs":  {"-", "- | - | -"},
	"Acme Web":   {"{1}5 m", "{1}24 m | 5 m | 1 h"},
}

// tbdLeadCells are the PR Lead Time cells of tbdData's projects (forsgren#423,
// Yves on #432): the median alone, or the mean, the median and the p90.
var tbdLeadCells = map[string][2]string{
	"Acme Shop":  {"2 h", "3 h | 2 h | -"},
	"Acme Tools": {"{3}-", "{3}1 d 6 h | - | -"},
	"Acme Docs":  {"{5}-", "{5}- | - | -"},
	"Acme Web":   {"{4,5}10 h", "{4,5}20 h | 10 h | 1 d 6 h"},
}

// leadState is the pull requests state cell for the figures: one column, or
// three across the group of all of them.
func leadState(all bool, text string) string {
	if all {
		return "@3" + text
	}
	return text
}

// at is the one of the two cells that the figures show.
func at(cells [2]string, all bool) string {
	if all {
		return cells[1]
	}
	return cells[0]
}

// noLeads are the Mainline Lead Times of tbdData's projects without a pull
// request merged in the window.
func noLeads() []metrics.MainlineLeadTime {
	leads := tbdLeads()
	for i := range leads {
		leads[i] = metrics.MainlineLeadTime{Project: leads[i].Project}
	}
	return leads
}

// uncollected is tbdData with no data/pulls.csv beside the history: the pull
// requests have not been collected yet (forsgren#256, step 2).
func uncollected() Data {
	data := tbdDataWith(noLeads())
	data.PullsUncollected = true
	return data
}

// notReadable is tbdData with collect refused the pull request read of a
// repository of Acme Tools and of Acme Docs (forsgren#337, step 2): Acme
// Tools' cut pull request stays read, Acme Docs has none.
func notReadable() Data {
	data := tbdData()
	data.MainlineLead[1].NotReadable = true
	data.MainlineLead[2].NotReadable = true
	return data
}

// tbdRow is the TBD page's row of project, as the template writes it with the
// figures all or the median only: its Mainline Interval cells (tbdIntervalCells),
// the cells of tbdTimeCells, its pull requests cells lead, the cells of
// tbdCountCells and its Developers count (forsgren#397, step 5; order of
// forsgren#418; forsgren#423).
func tbdRow(all bool, project, lead, developers string) string {
	return "<th scope=\"row\">" + project + "</th>\n            " + tds(at(tbdIntervalCells[project], all)) +
		"\n            " + tds(at(tbdTimeCells[project], all)) + "\n            " + tds(lead) + "\n            " +
		tds(at(tbdCountCells[project], all)) + "\n            " + tds(developers) + "\n"
}

// tds are the cells of cells, parted by " | ", as the template writes a row's
// cells: one td on each line.
func tds(cells string) string {
	parts := strings.Split(cells, " | ")
	for i, c := range parts {
		parts[i] = tdOf(c)
	}
	return strings.Join(parts, "\n            ")
}

// tdOf is the cell c as the template writes it: a cell starting with @N is a
// state cell across N columns, one starting with {N,M} carries the notes N and
// M, any other is plain.
func tdOf(c string) string {
	if rest, spans := strings.CutPrefix(c, "@"); spans {
		return stateTd(rest)
	}
	if rest, noted := strings.CutPrefix(c, "{"); noted {
		return notedTd(notedOf(rest))
	}
	return "<td>" + c + "</td>"
}

// stateTd is the state cell rest, N columns wide and then its text; across one it is a plain
// cell (forsgren#423).
func stateTd(rest string) string {
	columns, text := rest[:1], rest[1:]
	if columns == "1" {
		return "<td>" + text + "</td>"
	}
	return "<td colspan=\"" + columns + "\">" + text + "</td>"
}

// notedCell is a cell of a test's cells string with notes: its value and the
// numbers of its notes (forsgren#394, step 2).
type notedCell struct {
	value   string
	numbers []int
}

// notedOf reads a cell written {2,5}value: the notes 2 and 5 on value.
func notedOf(rest string) notedCell {
	list, value, _ := strings.Cut(rest, "}")
	cell := notedCell{value: value}
	for _, n := range strings.Split(list, ",") {
		number, _ := strconv.Atoi(n)
		cell.numbers = append(cell.numbers, number)
	}
	return cell
}

// notedTd is the cell as the template writes it (forsgren#394, step 2):
// described by each note's line, the marker (N) after the value with a
// visually hidden "note" before it.
func notedTd(c notedCell) string {
	ids, marks := make([]string, len(c.numbers)), ""
	for i, n := range c.numbers {
		ids[i] = "tbd-note-" + strconv.Itoa(n)
		marks += ` <span class="visually-hidden">note</span> (` + strconv.Itoa(n) + `)`
	}
	return `<td aria-describedby="` + strings.Join(ids, " ") + `">` + c.value + marks + `</td>`
}

// tbdGroups are the group headers of the TBD table with all the figures, in
// order, each with its columns' headers (forsgren#397, step 5, Yves's ruling
// on #401; forsgren#423): the units are in the names, durations and counts of
// commits.
var tbdGroups = []struct {
	name    string
	columns []string
	hidden  string // the measure, said after each column's word in its accessible name
}{
	{"Mainline Interval", []string{"mean", "median", "p90"}, ""},
	{"Time to main per commit (duration)", []string{"mean", "median", "p90"}, "time to main"},
	{"Time to deploy per commit (duration)", []string{"mean", "median", "p90"}, "time to deploy"},
	{"PR Lead Time", []string{"mean", "median", "p90"}, ""},
	{"Volume", []string{"Commits", "Pushes", "Deployments"}, ""},
	{"Commits per push", []string{"mean", "median", "p90"}, "commits per push"},
	{"Commits per deployment", []string{"mean", "median", "p90"}, "commits per deployment"},
	{"Shares of commits", []string{"Direct", "PR", "Unknown", "Bots"}, ""},
	{"Developers", []string{"developers"}, ""},
}

// shortHeaders are the column headers written short (forsgren#403), each with
// the accessible name that says the full meaning.
var shortHeaders = map[string]string{
	"PR":      "pull request share of commits",
	"Unknown": "unknown author share of commits",
}

// tbdHeaders are the two header rows' cells of the TBD table with all the
// figures as the template writes them: Project over both, the groups on top,
// their columns beneath.
func tbdHeaders() (top, beneath string) {
	const indent = "\n            "
	tops := []string{`<th scope="col" rowspan="2">Project</th>`}
	var columns []string
	for _, g := range tbdGroups {
		tops = append(tops, `<th scope="colgroup" colspan="`+strconv.Itoa(len(g.columns))+`">`+g.name+`</th>`)
		for _, c := range g.columns {
			label := ""
			if full, ok := shortHeaders[c]; ok {
				label = ` aria-label="` + full + `"`
			} else if g.hidden != "" {
				label = ` aria-label="` + c + ` ` + g.hidden + `"`
			}
			columns = append(columns, `<th scope="col"`+label+`>`+c+`</th>`)
		}
	}
	return strings.Join(tops, indent), strings.Join(columns, indent)
}

// medianHeaders are the headers of the TBD table with the median only, in one
// row (forsgren#423): a header for each measure that says it is the median, the
// shares named by what they are shares of in the accessible name.
var medianHeaders = []struct{ text, label string }{
	{"Project", ""},
	{"Mainline Interval (median)", ""},
	{"Time to main per commit (median duration)", ""},
	{"Time to deploy per commit (median duration)", ""},
	{"PR Lead Time (median)", ""},
	{"Commits", ""}, {"Pushes", ""}, {"Deployments", ""},
	{"Commits per push (median)", ""},
	{"Commits per deployment (median)", ""},
	{"Direct share", "direct share of commits"},
	{"PR share", "pull request share of commits"},
	{"Unknown share", "unknown author share of commits"},
	{"Bots share", "bot share of commits"},
	{"Developers", ""},
}

// medianHead is the thead of the table with the median only: one row.
func medianHead() string {
	cells := make([]string, len(medianHeaders))
	for i, h := range medianHeaders {
		label := ""
		if h.label != "" {
			label = ` aria-label="` + h.label + `"`
		}
		cells[i] = `<th scope="col"` + label + `>` + h.text + `</th>`
	}
	return "<thead>\n          <tr>\n            " + strings.Join(cells, "\n            ") +
		"\n          </tr>\n        </thead>"
}

// noHumanPulls is the pull requests cell of a project without a human pull
// request in the window, in the default figures: a dash (forsgren#390, step
// 2).
const noHumanPulls = "-"

// TestTbdPageHasOneHeaderRowWithTheMedianOnly (forsgren#423): by default, and
// with tbd_figures median, the table has one header row: a column for each
// measure whose header says it is the median, the shares and the volumes with
// their own names, no second row and no column group.
func TestTbdPageHasOneHeaderRowWithTheMedianOnly(t *testing.T) {
	for name, figures := range map[string]string{"default": "", "median": "median"} {
		data := tbdData()
		data.TbdFigures = figures
		got := rendered(t, "tbd.html", data)
		wantAll(t, name, got, medianHead())
		wantNone(t, name, got, "colgroup", "rowspan", `>mean<`, `>p90<`, `>deviation<`, `>gaps<`, "Shares of commits")
	}
}

// TestTbdPageHasTwoLevelHeadersWithAllTheFigures (forsgren#397, step 5, Yves's
// ruling on #401; forsgren#423): with tbd_figures all the groups are on top in
// the order of the ruling, each scoped as a column group, mean, median and p90
// beneath each measure, the Mainline Interval and the PR Lead Time included,
// which have no deviation and no gaps column any more; durations say so, batch
// sizes are commits per push and per deployment; the old direct and batch size
// columns and the unknown authors of Developers are gone.
func TestTbdPageHasTwoLevelHeadersWithAllTheFigures(t *testing.T) {
	top, beneath := tbdHeaders()
	data := tbdData()
	data.TbdFigures = "all"
	got := rendered(t, "tbd.html", data)
	const open, between, end = "<thead>\n          <tr>\n            ", "\n          </tr>\n          <tr>\n            ",
		"\n          </tr>\n        </thead>"
	wantAll(t, "tbd.html", got, open+top+between+beneath+end)
	wantNone(t, "tbd.html", got, `<th scope="col">direct</th>`, `<th scope="col">batch size</th>`,
		`<th scope="col">unknown authors</th>`, `>deviation<`, `>gaps<`, `>pull requests<`)
}

// TestTbdPageShowsTheRowsOfEachProject (forsgren#397, step 5; forsgren#423):
// volume, shares, the four measures, the pull requests lead time, the Mainline
// Interval and the developers count; a project whose push read was refused,
// or with no push collected yet, has one cell across the push groups and no
// deployment number in its place; the Deployments cell is a number, releases
// included (forsgren#403). By default the median of each measure; the PR Lead
// Time cell has no count, no cut count and no share, only its notes' markers.
func TestTbdPageShowsTheRowsOfEachProject(t *testing.T) {
	got := rendered(t, "tbd.html", tbdData())
	wantAll(t, "tbd.html", got,
		tbdRow(false, "Acme Shop", at(tbdLeadCells["Acme Shop"], false), "3"),
		tbdRow(false, "Acme Tools", at(tbdLeadCells["Acme Tools"], false), "1"),
		tbdRow(false, "Acme Docs", at(tbdLeadCells["Acme Docs"], false), "1"),
		tbdRow(false, "Acme Web", at(tbdLeadCells["Acme Web"], false), "12"))
	wantNone(t, "tbd.html", got, "pull requests merged within", "(1 cut)", "±")
}

// TestTbdPageShowsAllTheFiguresOfEachProject (forsgren#423): with tbd_figures
// all, each measure has its mean, median and p90, the Mainline Interval with
// the note on the mean cell, the PR Lead Time like the others, without its
// deviation, count, cut count and share.
func TestTbdPageShowsAllTheFiguresOfEachProject(t *testing.T) {
	got := rendered(t, "tbd.html", inFigures(tbdData(), true))
	wantAll(t, "tbd.html", got,
		tbdRow(true, "Acme Shop", at(tbdLeadCells["Acme Shop"], true), "3"),
		tbdRow(true, "Acme Tools", at(tbdLeadCells["Acme Tools"], true), "1"),
		tbdRow(true, "Acme Docs", at(tbdLeadCells["Acme Docs"], true), "1"),
		tbdRow(true, "Acme Web", at(tbdLeadCells["Acme Web"], true), "12"))
	wantNone(t, "tbd.html", got, "pull requests merged within", "(1 cut)", "±")
}

// inFigures is data with the figures of the key tbd_figures: all, or the
// median only.
func inFigures(data Data, all bool) Data {
	data.TbdFigures = "median"
	if all {
		data.TbdFigures = "all"
	}
	return data
}

// TestTbdPageSaysThePullRequestsAreNotCollectedYet (forsgren#256, step 2):
// without data/pulls.csv beside the history, every pull requests cell says the
// pull requests have not been collected yet, one cell across the group, never a
// dash, which is a project without a pull request merged in the window.
func TestTbdPageSaysThePullRequestsAreNotCollectedYet(t *testing.T) {
	const notYet = "No pull requests have been collected yet"
	for _, all := range []bool{false, true} {
		state := leadState(all, notYet)
		got := rendered(t, "tbd.html", inFigures(uncollected(), all))
		wantAll(t, "uncollected", got, tbdRow(all, "Acme Shop", state, "3"),
			tbdRow(all, "Acme Docs", state, "1"), tbdRow(all, "Acme Web", state, "12"))
		noneInWindow := rendered(t, "tbd.html", inFigures(tbdDataWith(noLeads()), all))
		wantNone(t, "collected, none in the window", noneInWindow, notYet)
		dashes := noHumanPulls
		if all {
			dashes = "- | - | -"
		}
		wantAll(t, "collected, none in the window", noneInWindow, tbdRow(all, "Acme Docs", dashes, "1"))
	}
}

// TestTbdPageSaysThePullRequestsAreNotReadable (forsgren#337, step 2): a
// project collect was refused the pull request read of shows "Pull requests
// not readable" in its pull requests cell, across the group when it has three,
// never the lead time of what was read nor the dash of no pull request, also
// while data/pulls.csv is absent; the other projects keep their cell.
func TestTbdPageSaysThePullRequestsAreNotReadable(t *testing.T) {
	const refused, notYet = "Pull requests not readable", "No pull requests have been collected yet"
	for _, all := range []bool{false, true} {
		state := leadState(all, refused)
		got := rendered(t, "tbd.html", inFigures(notReadable(), all))
		wantAll(t, "not readable", got, tbdRow(all, "Acme Tools", state, "1"),
			tbdRow(all, "Acme Docs", state, "1"),
			tbdRow(all, "Acme Shop", at(tbdLeadCells["Acme Shop"], all), "3"))
		uncollectedRefused := inFigures(notReadable(), all)
		uncollectedRefused.PullsUncollected = true
		got = rendered(t, "tbd.html", uncollectedRefused)
		wantAll(t, "not collected yet", got, tbdRow(all, "Acme Docs", state, "1"),
			tbdRow(all, "Acme Shop", leadState(all, notYet), "3"))
	}
}

// TestTbdPageRefusesMeasuresOfOtherProjects (forsgren#273, step 3;
// forsgren#397, step 5): the Developers, the Mainline Lead Times, the push and
// deployment measures and the deployment volumes are paired with the Mainline
// Intervals by project, so a render whose any of them is missing, one too
// many, or names another project in a row, fails instead of showing a number
// in the wrong row.
func TestTbdPageRefusesMeasuresOfOtherProjects(t *testing.T) {
	cases := map[string]func(*Data){
		"developers missing": func(d *Data) { d.Developers = d.Developers[:3] },
		"developers extra": func(d *Data) {
			d.Developers = append(d.Developers, metrics.Developers{Project: "Acme Gone", Count: 1})
		},
		"developers swapped": func(d *Data) { d.Developers[0], d.Developers[1] = d.Developers[1], d.Developers[0] },
		"leads missing":      func(d *Data) { d.MainlineLead = d.MainlineLead[:3] },
		"leads extra": func(d *Data) {
			d.MainlineLead = append(d.MainlineLead, metrics.MainlineLeadTime{Project: "Acme Gone"})
		},
		"leads swapped":   func(d *Data) { d.MainlineLead[0], d.MainlineLead[1] = d.MainlineLead[1], d.MainlineLead[0] },
		"pushes missing":  func(d *Data) { d.PushMeasures = d.PushMeasures[:3] },
		"pushes swapped":  func(d *Data) { d.PushMeasures[0], d.PushMeasures[1] = d.PushMeasures[1], d.PushMeasures[0] },
		"deploys missing": func(d *Data) { d.DeployMeasures = d.DeployMeasures[:3] },
		"deploys swapped": func(d *Data) {
			d.DeployMeasures[0], d.DeployMeasures[1] = d.DeployMeasures[1], d.DeployMeasures[0]
		},
		"volumes missing": func(d *Data) { d.DeploymentVolumes = d.DeploymentVolumes[:3] },
		"volumes swapped": func(d *Data) {
			d.DeploymentVolumes[0], d.DeploymentVolumes[1] = d.DeploymentVolumes[1], d.DeploymentVolumes[0]
		},
	}
	for name, change := range cases {
		data := tbdData()
		change(&data)
		var got bytes.Buffer
		if err := Render(&got, "tbd.html", data); err == nil {
			t.Errorf("%s: want the render to fail, got:\n%s", name, got.String())
		}
	}
}

// TestTbdPageGolden (forsgren#253, step 4 of 7): the TBD page is a root page,
// tbd.html, with a table of a row per project; with no projects, or no
// Mainline Interval read yet, one line says why in place of the table. Its
// Mainline Lead Time column (forsgren#256, step 2) has a golden with data,
// one with no pull request in the window, one before the pull requests were
// collected and one with refused pull request reads (forsgren#337, step 2);
// the golden with data holds the push groups of forsgren#397, step 5, with
// both of their states. These are the page with the median only, the default;
// the page with all the figures (tbd_figures: all, forsgren#423) has a golden
// with data and one with refused pull request reads.
func TestTbdPageGolden(t *testing.T) {
	noProjects := calculated()
	noProjects.NoProjects = true
	checkPageGolden(t, "tbd.html", "testdata/tbd.golden.html", tbdData())
	checkPageGolden(t, "tbd.html", "testdata/tbd.no-data.golden.html", calculated())
	checkPageGolden(t, "tbd.html", "testdata/tbd.no-projects.golden.html", noProjects)
	checkPageGolden(t, "tbd.html", "testdata/tbd.lead-no-data.golden.html", tbdDataWith(noLeads()))
	checkPageGolden(t, "tbd.html", "testdata/tbd.lead-not-collected.golden.html", uncollected())
	checkPageGolden(t, "tbd.html", "testdata/tbd.lead-not-readable.golden.html", notReadable())
	checkPageGolden(t, "tbd.html", "testdata/tbd.all.golden.html", inFigures(tbdData(), true))
	checkPageGolden(t, "tbd.html", "testdata/tbd.all-lead-not-readable.golden.html", inFigures(notReadable(), true))
}

// TestTbdPageHasItsHeadingAndTable (forsgren#253): the title and the h1 (id
// tbd-heading) name trunk-based development; the table is the h1's region,
// with no caption, and a row header for each project.
func TestTbdPageHasItsHeadingAndTable(t *testing.T) {
	got := rendered(t, "tbd.html", tbdData())
	wantAll(t, "tbd.html", got, "<title>Trunk-based development [TBD] · ",
		`<h1 id="tbd-heading">Trunk-based development [TBD]</h1>`, `aria-labelledby="tbd-heading"`,
		`<th scope="col">Project</th>`, `<th scope="row">Acme Shop</th>`,
		`<th scope="row">Acme Tools</th>`, `<th scope="row">Acme Docs</th>`, `<th scope="row">Acme Web</th>`)
	wantNone(t, "tbd.html", got, "<caption", "metrics are coming to this page")
}

// TestTbdPageHasNoExplanationAndNoLeadTimeLine (forsgren#271): the h1 is
// followed by the table, or by its one line; the explanation of the Mainline
// Interval and of the Mainline Lead Time is the legend's, not the page's.
func TestTbdPageHasNoExplanationAndNoLeadTimeLine(t *testing.T) {
	for name, data := range map[string]Data{"data": tbdData(), "no data": calculated()} {
		wantNone(t, name, rendered(t, "tbd.html", data), "sample standard deviation", "deployments of the last",
			"Mainline Lead Time is", "A dash is", "each commit once", "lower bound, so")
	}
}

// TestTbdTitleIsYvesWording (forsgren#271, forsgren#409): the title and the
// h1 of the TBD page read exactly "Trunk-based development [TBD]", with no
// beta marker since the page left beta; the History page keeps its marker
// (forsgren#198).
func TestTbdTitleIsYvesWording(t *testing.T) {
	const want = "Trunk-based development [TBD]"
	if got := calculated().TbdTitle(); got != want {
		t.Errorf("want the title %q, got %q", want, got)
	}
	wantNone(t, "tbd.html", rendered(t, "tbd.html", tbdData()), "(BETA)")
	history := rendered(t, "history.html", historyData())
	wantAll(t, "history.html", history, `<h1 id="history-heading">History (BETA)</h1>`)
}

// TestTbdPageSaysWhyItHasNoTable (forsgren#253): with no projects, or no
// Mainline Interval read, the page shows one line and no table.
func TestTbdPageSaysWhyItHasNoTable(t *testing.T) {
	noProjects := calculated()
	noProjects.NoProjects = true
	for name, c := range map[string]struct {
		data Data
		want string
	}{
		"no projects": {noProjects, "No projects are listed yet, so there is no Mainline Interval to show."},
		"no data":     {calculated(), "No commits have been collected yet, so there is no Mainline Interval to show."},
	} {
		got := rendered(t, "tbd.html", c.data)
		wantAll(t, name, got, "<p>"+c.want+"</p>")
		wantNone(t, name, got, "<table")
	}
}

// TestTbdPageIsAfterHistoryInTheRootPages (forsgren#253): the page is one of
// the root pages, labelled TBD, after the History page.
func TestTbdPageIsAfterHistoryInTheRootPages(t *testing.T) {
	last := rootPages[len(rootPages)-1]
	if last.Name != TbdPage || last.Label != "TBD" {
		t.Errorf("want the last root page %q labelled TBD, got %+v", TbdPage, last)
	}
}

// TestTbdTableWrapsItsCells (forsgren#350): the TBD table's cells carry long
// notes, so the table is class wraps, never no-wrap: its cells break and its
// columns share the page's width, at a laptop and at a phone width alike.
func TestTbdTableWrapsItsCells(t *testing.T) {
	got := rendered(t, "tbd.html", tbdData())
	wantAll(t, "tbd.html", got, `<table class="wraps">`)
	wantNone(t, "tbd.html", got, `class="no-wrap"`)
}
