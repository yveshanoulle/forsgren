package page

// The charts of the history page (forsgren#68): in a row's Trend cell, a
// small line chart of its score per period. The y axis is the DORA Quick
// Check score, 0 to 10, 10 at the top, the same for every chart; the x axis
// is the periods, oldest left. A period without a score is a gap: the line
// breaks there, and a period alone between gaps is a dot. The table beside it
// carries the same numbers, so the chart has a title and nothing else for a
// reader of the page; it is drawn in the text colour. The "chart" template
// (templates/layout/historychart.html) draws it; its size, margin and dot
// are the constants below, the one place of the chart's geometry.

import (
	"fmt"
	"strings"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// The chart's size, the margin around its lines and the radius of a dot, in
// the SVG's own units.
const (
	chartWidth  = 120
	chartHeight = 32
	chartMargin = 4
	chartDot    = 2
)

// HistoryChart is what the "chart" template draws: the title of the chart and
// its runs of periods.
type HistoryChart struct {
	Title string
	Runs  []ChartRun
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

// historyChart is the chart called title of the scores, one per period,
// oldest first; none when no period has a score.
func historyChart(title string, scores []score) *HistoryChart {
	var runs []ChartRun
	for _, run := range runsOf(scores) {
		runs = append(runs, drawRun(run, len(scores)))
	}
	if runs == nil {
		return nil
	}
	return &HistoryChart{Title: title, Runs: runs}
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

// chartTitle is the title of the chart of measure m for the row headed
// heading, over the periods of columns: "Deployment frequency score, Acme Shop
// (total): 2025 H2 to Last 6 months".
func chartTitle(m int, heading string, columns []metrics.Column) string {
	span := columns[0].Period.Label
	if len(columns) > 1 {
		span += " to " + columns[len(columns)-1].Period.Label
	}
	return fmt.Sprintf("%s score, %s: %s", historyMeasures[m], heading, span)
}
