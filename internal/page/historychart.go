package page

// The charts of the history page (forsgren#68, #212): above each project's
// block, one line chart with a line per measure of its score per period. The
// y axis is the DORA Quick Check score, 0 to 10, 10 at the top, the same for
// every chart; the x axis is the periods, oldest left. A period without a
// score is a gap: the line breaks there, and a period alone between gaps is a
// dot. The table below carries the same numbers, so the chart has a title and
// a legend and nothing else for a reader of the page. Each line has a colour
// (the class measure-N of styles.css, N the measure's index in
// historyMeasures) and a dash pattern, so colour is never the only cue. The
// "chart" template (templates/layout/historychart.html) draws it; its size,
// margin and dot are the constants below, the one place of the chart's
// geometry.

import (
	"fmt"
	"strings"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// The chart's size, the margin around its lines and the radius of a dot, in
// the SVG's own units.
const (
	chartWidth  = 480
	chartHeight = 160
	chartMargin = 8
	chartDot    = 3
)

// measureDashes are the dash patterns of the lines, by measure: Overall
// Performance solid, the five metrics each its own, the second cue of the
// legend.
var measureDashes = []string{"none", "12 4", "3 4", "12 4 3 4", "1 5", "6 3 1 3 1 3"}

// HistoryChart is what the "chart" template draws: the title of the chart and
// its lines, which the legend names.
type HistoryChart struct {
	Title   string
	Project string
	Lines   []ChartLine
}

// ChartLine is the line of one measure: its name, the CSS class that colours it,
// its dash pattern and its runs of periods.
type ChartLine struct {
	Name, Class, Dash string
	Runs              []ChartRun
}

// Width is the chart's width, for the template.
func (HistoryChart) Width() int { return chartWidth }

// Height is the chart's height, for the template.
func (HistoryChart) Height() int { return chartHeight }

// DotRadius is the radius of a period alone, for the template.
func (HistoryChart) DotRadius() int { return chartDot }

// ChartRun is a run of consecutive periods that have a score: a dot at X, Y
// for a period alone, else the Points of a polyline, both in the SVG's units.
type ChartRun struct {
	Dot    bool
	X, Y   string
	Points string
}

// historyChart is the chart called title of the scores of each measure, in
// the order of historyMeasures, one score per period, oldest first; a measure
// with no score in any period has no line, and none when no measure has one.
func historyChart(title string, scores [][]score) *HistoryChart {
	var lines []ChartLine
	for m, perPeriod := range scores {
		var runs []ChartRun
		for _, run := range runsOf(perPeriod) {
			runs = append(runs, drawRun(run, len(perPeriod)))
		}
		if runs != nil {
			lines = append(lines, ChartLine{Name: historyMeasures[m], Class: fmt.Sprintf("measure-%d", m),
				Dash: measureDashes[m], Runs: runs})
		}
	}
	if lines == nil {
		return nil
	}
	return &HistoryChart{Title: title, Lines: lines}
}

// point is a period's place in the chart: its index among the periods and its
// score.
type point struct {
	index int
	value float64
}

// runsOf are the runs of consecutive periods that have a score.
func runsOf(scores []score) [][]point {
	var runs [][]point
	for i, s := range scores {
		switch {
		case !s.ok:
		case i > 0 && scores[i-1].ok:
			runs[len(runs)-1] = append(runs[len(runs)-1], point{i, s.value})
		default:
			runs = append(runs, []point{{i, s.value}})
		}
	}
	return runs
}

// drawRun is the dot of a run of one period, else the polyline of the run, in
// a chart of periods periods.
func drawRun(run []point, periods int) ChartRun {
	if len(run) == 1 {
		x, y := place(run[0], periods)
		return ChartRun{Dot: true, X: fmt.Sprintf("%.1f", x), Y: fmt.Sprintf("%.1f", y)}
	}
	points := make([]string, len(run))
	for i, p := range run {
		x, y := place(p, periods)
		points[i] = fmt.Sprintf("%.1f,%.1f", x, y)
	}
	return ChartRun{Points: strings.Join(points, " ")}
}

// place is where p lies in a chart of periods periods: evenly spread between
// the margins, a single period in the middle, the score 10 at the top margin
// and 0 at the bottom one.
func place(p point, periods int) (x, y float64) {
	x = chartWidth / 2.0
	if periods > 1 {
		x = chartMargin + float64(p.index)*(chartWidth-2*chartMargin)/float64(periods-1)
	}
	return x, chartHeight - chartMargin - p.value/10*(chartHeight-2*chartMargin)
}

// chartScore is the score of the row for measure m of historyMeasures, 0 being
// the Overall Performance: none for a row without data, as its cells are
// dashes.
func chartScore(r Row, m int) score {
	switch {
	case !r.HasData():
		return score{}
	case m == 0:
		return r.overall()
	}
	return r.scores()[m-1]
}

// chartTitle is the title of the chart of the project headed name, over the
// periods of columns: "Scores of Acme Shop: 2025 H2 to Last 6 months".
func chartTitle(name string, columns []metrics.Column) string {
	span := columns[0].Period.Label
	if len(columns) > 1 {
		span += " to " + columns[len(columns)-1].Period.Label
	}
	return fmt.Sprintf("Scores of %s: %s", name, span)
}
