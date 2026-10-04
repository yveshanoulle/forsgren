package page

// The cells of the scoring view (forsgren#47): each metric's DORA Quick
// Check score (dora.dev/quickcheck) alone, "-" where the metric has no
// data, and Overall Performance, the mean of the scored metrics.

import (
	"fmt"
	"strconv"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// noScore is the cell of a metric with no score.
const noScore = "-"

// score is a metric's score, which it has only when the metric has data.
type score struct {
	value float64
	ok    bool
}

// scores are the row's five scores, in the table's column order.
func (r Row) scores() []score {
	return []score{
		{metrics.BandScore(r.Frequency.Band), r.Frequency.Band != 0},
		{metrics.BandScore(r.LeadTime.Band), r.LeadTime.HasCommits()},
		{metrics.BandScore(r.Recovery.Band), r.Recovery.Recoveries > 0},
		{metrics.PercentScore(r.ChangeFail.Percent()), r.ChangeFail.Deployments > 0},
		{metrics.PercentScore(r.Rework.Percent()), r.Rework.Deployments > 0},
	}
}

// ScoreCells are the row's five scores as cells: "9.3", "10", "0", with no
// trailing zero, and "-" for a metric without data.
func (r Row) ScoreCells() []string {
	var cells []string
	for _, s := range r.scores() {
		cell := noScore
		if s.ok {
			cell = strconv.FormatFloat(s.value, 'f', -1, 64)
		}
		cells = append(cells, cell)
	}
	return cells
}

// OverallCell is the row's Overall Performance to one decimal, "8.4": the
// mean of its scored metrics.
func (r Row) OverallCell() string {
	var scored []float64
	for _, s := range r.scores() {
		if s.ok {
			scored = append(scored, s.value)
		}
	}
	overall, _ := metrics.OverallScore(scored)
	return fmt.Sprintf("%.1f", overall)
}
