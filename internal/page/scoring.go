package page

// The cells of the scoring view (forsgren#47): each metric's DORA Quick
// Check score (dora.dev/quickcheck) alone, "-" where the metric has no
// data, and Overall Performance, the mean of the scored metrics.

import (
	"fmt"
	"strconv"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// noScore is the cell of a metric with no score, and of an Overall
// Performance with no scored metric.
const noScore = "-"

// score is a metric's score, which it has only when the metric has data.
type score struct {
	value float64
	ok    bool
}

// scores are the row's five scores, in the table's column order, each
// scored only when its metric has data. A score of 0 is observed
// performance in the lowest band, never a lack of data. Lead time, recovery
// time, change fail rate and rework rate have data exactly where their
// NumberCell is not "-". Deployment frequency has data when the recorded
// history holds a successful deployment, however old: a last success older
// than six months is observed performance in the lowest band and scores 0,
// while a project that never had one has the lowest band but no score, and
// the numbers view shows its 30-day count, 0.
func (r Row) scores() []score {
	return []score{
		{metrics.BandScore(r.Frequency.Band), r.Frequency.HasDeployments()},
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

// overall is the row's Overall Performance: the mean of its scored metrics,
// none when no metric is scored.
func (r Row) overall() score {
	var scored []float64
	for _, s := range r.scores() {
		if s.ok {
			scored = append(scored, s.value)
		}
	}
	value, ok := metrics.OverallScore(scored)
	return score{value, ok}
}

// OverallCell is the row's Overall Performance to one decimal, "8.4", "-"
// when no metric is scored.
func (r Row) OverallCell() string {
	overall := r.overall()
	if !overall.ok {
		return noScore
	}
	return fmt.Sprintf("%.1f", overall.value)
}

// separator joins a number and its score in a cell of the numbers and
// scoring page, the " · " of the menu and the footer (forsgren#55).
const separator = " · "

// NumberScoreCells are the row's five metrics as the numbers and scoring page
// shows them (forsgren#55): the number as the numbers page shows it, then its
// score, "12 · 6", "7% · 9.3", and "-" for a metric without data. The weekend
// deployments are not a metric and have no cell.
func (r Row) NumberScoreCells() []string {
	numbers := []string{r.Frequency.NumberCell(), r.LeadTime.NumberCell(), r.Recovery.NumberCell(),
		r.ChangeFail.NumberCell(), r.Rework.NumberCell()}
	cells := make([]string, len(numbers))
	for i, score := range r.ScoreCells() {
		cells[i] = numbers[i]
		if numbers[i] != noScore {
			cells[i] += separator + score
		}
	}
	return cells
}
