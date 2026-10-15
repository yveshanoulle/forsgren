package page

import (
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

// TestHistoryPageGolden (forsgren#68): the history page is a table per
// measure, Overall Performance first, a row per table row and a column per
// period, oldest first, each cell the number and its score as the numbers
// and scoring page writes them and a dash for a row that is unread or has no
// deployment yet.
func TestHistoryPageGolden(t *testing.T) {
	checkPageGolden(t, "history.html", "testdata/history.golden.html", historyData())
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
		"</svg></td>\n            <td>-</td>\n            <td>1 · 0</td>",
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

// TestHistoryChartsAreInlineSVGWithTitleAndNoScript (forsgren#68): every row
// of every group has a chart in its Trend cell, an inline SVG with a title
// that names the measure, the row and the periods it spans, drawn in the
// text colour, and with no script and no description.
func TestHistoryChartsAreInlineSVGWithTitleAndNoScript(t *testing.T) {
	got := rendered(t, "history.html", historyData())
	if n := strings.Count(got, "<svg role=\"img\""); n != 18 {
		t.Errorf("want a chart for each of the 18 rows (6 groups of 3), got %d", n)
	}
	for _, want := range []string{
		"<title>Deployment frequency score, Acme Shop (total): 2026 H1 to Last 6 months</title>",
		"<title>Overall Performance score, API: 2026 H1 to Last 6 months</title>",
		"<th scope=\"col\">Trend</th>",
		"stroke=\"currentcolor\"",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("history page does not contain %q", want)
		}
	}
	for _, not := range []string{"<script", "<desc", "javascript", "#"} {
		if strings.Contains(strings.ToLower(got), not) {
			t.Errorf("history page contains %q", not)
		}
	}
}

// TestChartBreaksAtAGapAndDrawsASinglePointAsADot (forsgren#68): a period
// without a score is a gap, never a zero: the line breaks there, a run of
// two periods or more is a polyline and a period alone between gaps a dot.
// The scale is 0 to 10 for every chart, 10 at the top.
func TestChartBreaksAtAGapAndDrawsASinglePointAsADot(t *testing.T) {
	scores := []score{{10, true}, {0, false}, {5, true}, {0, true}}
	var drawn strings.Builder
	if err := pages["history.html"].set.ExecuteTemplate(&drawn, "chart", historyChart("Test", scores)); err != nil {
		t.Fatal(err)
	}
	got := drawn.String()
	for _, want := range []string{
		`<svg role="img" viewBox="0 0 120 32" width="120" height="32"><title>Test</title>`,
		`<circle cx="4.0" cy="4.0" r="2" fill="currentcolor"/>`,
		`<polyline points="78.7,16.0 116.0,28.0" fill="none" stroke="currentcolor"/></svg>`,
	} {
		if !strings.Contains(got, want) {
			t.Errorf("chart does not contain %q, got %s", want, got)
		}
	}
	if strings.Contains(got, "41.3") {
		t.Errorf("chart draws the period without a score: %s", got)
	}
	if none := historyChart("Test", []score{{0, false}, {0, false}}); none != nil {
		t.Errorf("want no chart when no period has a score, got %+v", none)
	}
}

// TestHistoryPageIsMarkedBeta (forsgren#198): the History page's title and
// heading say "History (beta)", the legend's section heading says "History
// page (beta)", and the menu label stays "History".
func TestHistoryPageIsMarkedBeta(t *testing.T) {
	history := rendered(t, "history.html", historyData())
	wantAll(t, "history.html", history, "<title>History (beta) · ", `<h1 id="history-heading">History (beta)</h1>`,
		`<a href="days.html">Daily</a> · <span aria-current="page">History</span></nav>`)
	wantAll(t, "legend.html", rendered(t, "legend.html", calculated()), "<h2>History page (beta)</h2>")
	wantNone(t, "index.html", rendered(t, "index.html", calculated()), "(beta)")
}

// historyHowToRead is the line under the History heading (forsgren#198).
const historyHowToRead = `<p>Each column is a period: the calendar half-years, then the last 6 months. ` +
	`A cell is the number and its score (0 to 10), number · score. Trend draws the score over the periods.</p>`

// TestHistoryPageSaysHowToReadItUnderTheHeading (forsgren#198): right under
// the heading, with history and without, one line says what a column, a cell
// and the Trend are; the legend already says the same at length, so it gains
// no sentence.
func TestHistoryPageSaysHowToReadItUnderTheHeading(t *testing.T) {
	for name, data := range map[string]Data{"with history": historyData(), "without": calculated()} {
		wantAll(t, name, rendered(t, "history.html", data),
			`<h1 id="history-heading">History (beta)</h1>`+"\n    "+historyHowToRead)
	}
}
