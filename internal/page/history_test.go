package page

import (
	"fmt"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// historyShop is Acme Shop's total in a period: deployments counted, with the
// bands that go with them.
func historyShop(deployments int) metrics.Row {
	return metrics.Row{
		Level: metrics.ProjectRow, Name: "Acme Shop",
		Frequency: metrics.Frequency{InWindow: deployments, Last180: deployments, Band: metrics.DailyToWeekly,
			Latest: time.Date(2026, 5, 1, 9, 30, 0, 0, time.UTC)},
		LeadTime:   metrics.LeadTime{Commits: 48, Median: 2*time.Hour + 7*time.Minute, Band: metrics.LessThanOneDay},
		Recovery:   metrics.Recovery{Recoveries: 2, Median: 3 * time.Hour, Band: metrics.LessThanOneDay},
		ChangeFail: metrics.ChangeFailRate{Deployments: 15, FailedDeployments: 3, Failed: 3, Band: metrics.TwentyPercent},
		Rework:     metrics.ReworkRate{Deployments: 12, Rework: 2, Band: metrics.TwentyPercent},
	}
}

// historyData is the history page's data: two columns, the half-year 2026 H1
// and the rolling last 6 months. Acme Shop and its service API have numbers
// in both; Acme Tools has no deployment in the half-year and, in the last 6
// months, one failed deployment and one that recovered it (forsgren#68).
func historyData() Data {
	api := historyShop(5)
	api.Level, api.Name = metrics.LabelRow, "API"
	tools := metrics.Row{Level: metrics.ProjectRow, Name: "Acme Tools"}
	recovered := tools
	recovered.Frequency = metrics.Frequency{InWindow: 1, Band: metrics.LessThanSixMonthly,
		Latest: time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC)}
	recovered.LeadTime = metrics.LeadTime{Commits: 2, Median: 25 * time.Minute, Band: metrics.LessThanOneHour}
	recovered.Recovery = metrics.Recovery{Recoveries: 1, Median: 40 * time.Hour, Band: metrics.OneDayToOneWeek}
	recovered.ChangeFail = metrics.ChangeFailRate{Deployments: 2, FailedDeployments: 1, Failed: 1,
		Band: metrics.FortyPercent}
	recovered.Rework = metrics.ReworkRate{Deployments: 1, Rework: 1, Band: metrics.HundredPercent}
	data := calculated()
	data.History = []metrics.Column{
		{
			Period: metrics.Period{Label: "2026 H1"},
			Rows:   []metrics.Row{historyShop(40), api, tools},
		},
		{
			Period: metrics.Period{Label: "Last 6 months", End: time.Date(2026, 10, 3, 12, 0, 0, 0, time.UTC), Rolling: true},
			Rows:   []metrics.Row{historyShop(30), api, recovered},
		},
	}
	return data
}

// TestHistoryPageGolden (forsgren#68, #211): the history page is one table with
// a block per project, the project's total and its labels each with a row per
// measure, Overall Performance first, and a column per period, oldest first,
// each cell the number and its score as the numbers and scoring page writes
// them and a dash for a row that is unread or has no deployment yet.
func TestHistoryPageGolden(t *testing.T) {
	checkPageGolden(t, "history.html", "testdata/history.golden.html", historyData())
}

// TestHistoryPageGroupsRowsPerProject (forsgren#211): the table has one tbody
// per project, headed by the project's name; in it the project's total and then
// each label, each with the six measures in order, Overall Performance first.
// No measure heads a group of rows of every project.
func TestHistoryPageGroupsRowsPerProject(t *testing.T) {
	got := rendered(t, "history.html", historyData())
	if n := strings.Count(got, "<tbody>"); n != 2 {
		t.Errorf("want a tbody for each of the 2 projects, got %d", n)
	}
	wantAll(t, "history.html", got,
		`<th scope="rowgroup" colspan="3">Acme Shop</th>`, `<th scope="rowgroup" colspan="3">Acme Tools</th>`)
	wantNone(t, "history.html", got, `scope="rowgroup" colspan="3">Overall Performance`,
		`scope="rowgroup" colspan="3">Deployment frequency`)
	var order []string
	for _, heading := range []string{"Acme Shop", "Overall Performance", "Deployment frequency", "Lead time for changes",
		"Failed deployment recovery time", "Change fail rate", "Deployment rework rate",
		"API: Overall Performance", "API: Deployment frequency", "API: Deployment rework rate", "Acme Tools"} {
		order = append(order, ">"+heading+"</th>")
	}
	at := 0
	for _, want := range order {
		i := strings.Index(got[at:], want)
		if i < 0 {
			t.Fatalf("history page does not have %q after offset %d, in this order", want, at)
		}
		at += i + len(want)
	}
}

// TestHistoryPageCellsAreNumbersAndScores (forsgren#68): one row of the
// frequency table, verbatim, and the dashes of the unread and empty rows.
func TestHistoryPageCellsAreNumbersAndScores(t *testing.T) {
	data := historyData()
	data.History[0].Rows[1] = metrics.Row{Level: metrics.LabelRow, Name: "API", Unread: true}
	got := rendered(t, "history.html", data)
	for _, want := range []string{
		"<td>40 · 6</td>\n            <td>30 · 6</td>",
		"<td>-</td>\n            <td>5 · 6</td>",
		"<td>-</td>\n            <td>1 · 0</td>",
		"<th scope=\"col\">Last 6 months to 2026-10-03</th>",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("history page does not contain %q", want)
		}
	}
}

// TestHistoryPageWithoutHistoryGolden (forsgren#68): with no table to show the
// history page says why in one line: no projects, a history_days under 180
// (naming the fix), or no history collected yet.
func TestHistoryPageWithoutHistoryGolden(t *testing.T) {
	noProjects, tooShort, nothingYet := calculated(), calculated(), calculated()
	noProjects.NoProjects = true
	tooShort.HistoryDays = 90
	checkPageGolden(t, "history.html", "testdata/history.no-projects.golden.html", noProjects)
	checkPageGolden(t, "history.html", "testdata/history.short.golden.html", tooShort)
	checkPageGolden(t, "history.html", "testdata/history.no-data.golden.html", nothingYet)
}

// projectBlock is the part of the history page between the tbody opening of
// the project headed name and its closing.
func projectBlock(t *testing.T, page, name string) string {
	t.Helper()
	start := strings.Index(page, `<th scope="rowgroup" colspan="3">`+name+`</th>`)
	if start < 0 {
		t.Fatalf("history page has no block for %q", name)
	}
	return page[start : start+strings.Index(page[start:], "</tbody>")]
}

// TestHistoryChartIsOnePerProjectAboveItsBlock (forsgren#212): each project's
// tbody has, right after the row with the project's name, one row with a cell
// as wide as the table (row headings plus periods, there is no Trend column
// any more) that holds the project's chart, an inline SVG with a title, no
// script and no description; the rows of the measures come after it, and no row
// has a chart of its own.
func TestHistoryChartIsOnePerProjectAboveItsBlock(t *testing.T) {
	got := rendered(t, "history.html", historyData())
	if n := strings.Count(got, `<svg role="img"`); n != 2 {
		t.Errorf("want a chart for each of the 2 projects, got %d", n)
	}
	wantNone(t, "history.html", got, `<th scope="col">Trend</th>`, "Trend draws", "<td><svg")
	for _, project := range []string{"Acme Shop", "Acme Tools"} {
		block := projectBlock(t, got, project)
		head := `<th scope="rowgroup" colspan="3">` + project + "</th>\n          </tr>\n" +
			"          <tr>\n            <td colspan=\"3\">"
		wantAll(t, project, block, head, "<title>Scores of "+project+": 2026 H1 to Last 6 months</title>")
		if !strings.Contains(block, "<svg") || strings.Index(block, "<svg") > strings.Index(block, `<th scope="row">`) {
			t.Errorf("%s: want the chart before the first measure row", project)
		}
	}
	wantNone(t, "history.html", got, "<script", "<desc", "javascript", "#")
}

// TestHistoryChartDrawsOneLinePerMeasureAndALegendNamesThem (forsgren#212): the
// chart draws a line for each measure that has a score, in the order of the
// table and each in its own class (measure-0 for Overall Performance to
// measure-5), and a legend under it names each line with its colour and a
// dash pattern, a second cue that works without colour; no two lines share a
// pattern. Acme Tools has scores in the last 6 months only, so its chart draws
// dots and its legend still names every measure.
func TestHistoryChartDrawsOneLinePerMeasureAndALegendNamesThem(t *testing.T) {
	got := rendered(t, "history.html", historyData())
	shop := projectBlock(t, got, "Acme Shop")
	patterns := map[string]bool{}
	last := -1
	for m, name := range historyMeasures {
		class := fmt.Sprintf(`<g class="measure-%d"`, m)
		i := strings.Index(shop, class)
		if i < 0 || i < last {
			t.Fatalf("want the line %q (%s) after the previous one", name, class)
		}
		last = i
		legend := regexp.MustCompile(`<li><span class="measure-` + fmt.Sprint(m) +
			`"><svg class="swatch"[^>]*><line [^>]*stroke-dasharray="([^"]*)"[^>]*/></svg></span> ` +
			`<span class="visually-hidden">Acme Shop: </span>` + name + `</li>`)
		found := legend.FindStringSubmatch(shop)
		if found == nil {
			t.Fatalf("want a legend item for %q with its swatch in class measure-%d", name, m)
		}
		if patterns[found[1]] {
			t.Errorf("the dash pattern %q is used by two lines", found[1])
		}
		patterns[found[1]] = true
	}
	wantAll(t, "Acme Tools", projectBlock(t, got, "Acme Tools"), "<circle", `<ul class="legend">`)
}

// TestHistoryChartColoursReachContrastInLightAndDark (forsgren#212): the six
// line colours are light-dark(light, dark) in styles.css, each at 4.5:1 or
// more on the page background in its mode, like the trend arrows; Overall
// Performance is black and white, Deployment frequency red and Lead time for
// changes green, and the six are six different colours in each mode.
func TestHistoryChartColoursReachContrastInLightAndDark(t *testing.T) {
	css := stylesCSS(t)
	seenLight, seenDark := map[string]bool{}, map[string]bool{}
	for m := range historyMeasures {
		class := fmt.Sprintf("measure-%d", m)
		light, dark := trendColours(t, css, class)
		wantContrast(t, swatch{class, "light", light}, lightCanvases)
		wantContrast(t, swatch{class, "dark", dark}, darkCanvases)
		if seenLight[light] || seenDark[dark] {
			t.Errorf(".%s repeats the colour %s / %s of another line", class, light, dark)
		}
		seenLight[light], seenDark[dark] = true, true
		want := map[int][2]string{0: {"#000000", "#ffffff"}, 1: {"#b3261e", "#ff8a80"}, 2: {"#1b6e2f", "#7fd98f"}}[m]
		if want != [2]string{} && [2]string{light, dark} != want {
			t.Errorf(".%s is %s / %s, want %s / %s", class, light, dark, want[0], want[1])
		}
	}
}

// TestChartBreaksAtAGapAndDrawsASinglePointAsADot (forsgren#68): a period
// without a score is a gap, never a zero: the line breaks there, a run of
// two periods or more is a polyline and a period alone between gaps a dot.
// The scale is 0 to 10 for every chart, 10 at the top (forsgren#212: the chart
// of a project, a group per line).
func TestChartBreaksAtAGapAndDrawsASinglePointAsADot(t *testing.T) {
	scores := []score{{10, true}, {0, false}, {5, true}, {0, true}}
	var drawn strings.Builder
	chart := historyChart("Test", [][]score{scores})
	if err := pages["history.html"].set.ExecuteTemplate(&drawn, "chart", chart); err != nil {
		t.Fatal(err)
	}
	got := drawn.String()
	for _, want := range []string{
		`<svg role="img" viewBox="0 0 480 160" width="480" height="160"><title>Test</title>`,
		`<circle cx="8.0" cy="8.0" r="3" fill="currentcolor" stroke="none"/>`,
		`<polyline points="317.3,80.0 472.0,152.0"/></g></svg>`,
	} {
		if !strings.Contains(got, want) {
			t.Errorf("chart does not contain %q, got %s", want, got)
		}
	}
	if strings.Contains(got, "162.7") {
		t.Errorf("chart draws the period without a score: %s", got)
	}
	if none := historyChart("Test", [][]score{{{0, false}, {0, false}}}); none != nil {
		t.Errorf("want no chart when no period has a score, got %+v", none)
	}
}

// TestHistoryPageIsMarkedBeta (forsgren#198): the History page's title and
// heading say "History (BETA)", the legend's section heading says "History
// page (BETA)", and the menu label stays "History".
func TestHistoryPageIsMarkedBeta(t *testing.T) {
	history := rendered(t, "history.html", historyData())
	wantAll(t, "history.html", history, "<title>History (BETA) · ", `<h1 id="history-heading">History (BETA)</h1>`,
		`<a href="days.html">Daily</a> · <span aria-current="page">History</span> · <a href="tbd.html">TBD</a>`+
			` · <a href="week.html">Week</a> · <a href="data.html">Data</a></nav>`)
	wantAll(t, "legend.html", rendered(t, "legend.html", calculated()), "<h2>History page (BETA)</h2>")
	wantNone(t, "index.html", rendered(t, "index.html", calculated()), "(BETA)")
}

// historyHowToRead is the line under the History heading (forsgren#198).
const historyHowToRead = `<p>Each column is a period: the calendar half-years, then the last 6 months. ` +
	`A cell is the number and its score (0 to 10), number · score.`

// historyTrendToRead is what the line adds while the charts are shown.
const historyTrendToRead = ` The chart above each project draws the score of each measure over the periods.`

// TestHistoryPageSaysHowToReadItUnderTheHeading (forsgren#198): right under
// the heading, one line says what a column and a cell are, and what the charts
// are unless the table has a single period column and so no chart; the
// legend already says the same at length.
func TestHistoryPageSaysHowToReadItUnderTheHeading(t *testing.T) {
	for name, tc := range map[string]struct {
		data Data
		line string
	}{
		"two periods": {historyData(), historyHowToRead + historyTrendToRead + "</p>"},
		"none":        {calculated(), historyHowToRead + historyTrendToRead + "</p>"},
	} {
		wantAll(t, name, rendered(t, "history.html", tc.data),
			`<h1 id="history-heading">History (BETA)</h1>`+"\n    "+tc.line)
	}
}

// TestHistoryPageWithOnePeriodSaysWhyUnderTheHowToReadLine (forsgren#198): with
// only the last 6 months, the page has the notice under the how-to-read line;
// with two columns it has none.
func TestHistoryPageWithOnePeriodSaysWhyUnderTheHowToReadLine(t *testing.T) {
	data := historyData()
	data.History, data.FirstDeployment, data.HistoryDays = data.History[1:], day(time.October, 2, 9, 30), 365
	const notice = "<p>Only the last 6 months have data so far: the first deployment is 2026-10-02. " +
		"The first half-year, 2026 H2, appears on 2027-01-01.</p>"
	wantAll(t, "history.html", rendered(t, "history.html", data), historyHowToRead+"</p>\n    "+notice)
	checkPageGolden(t, "history.html", "testdata/history.one-period.golden.html", data)
	wantNone(t, "history.html", rendered(t, "history.html", historyData()), "Only the last 6 months")
}

// TestHistoryPageLeavesOutTheChartsBelowTwoPeriods (forsgren#198): with
// one period column the table has no chart and a group header as wide as the
// row headings plus that one column; with two it has the charts and a header
// that is one wider (forsgren#212: there is no Trend column any more).
func TestHistoryPageLeavesOutTheChartsBelowTwoPeriods(t *testing.T) {
	one := historyData()
	one.History = one.History[1:]
	got := rendered(t, "history.html", one)
	wantNone(t, "one period", got, "<svg", `colspan="3"`, "The chart above", `class="legend"`)
	wantAll(t, "one period", got, `colspan="2"`)
	two := rendered(t, "history.html", historyData())
	wantAll(t, "two periods", two, "<svg", `colspan="3"`, "The chart above each project")
}
