package page

// The scores of the levels the legend lists (forsgren#79): each comes from
// the function the scoring view scores with, so the legend cannot drift from
// the scoring view.

import "github.com/yveshanoulle/forsgren/internal/metrics"

// bandScores are the scores of the bands from first to last, as the scoring
// view gives them.
func bandScores[B ~int](first, last B) []string {
	var scores []string
	for b := first; b <= last; b++ {
		scores = append(scores, scoreCell(metrics.BandScore(b)))
	}
	return scores
}

// FrequencyScores are the scores of deployment frequency's six levels,
// fastest first.
func (d Data) FrequencyScores() []string {
	return bandScores(metrics.OnDemand, metrics.LessThanSixMonthly)
}

// LeadTimeScores are the scores of lead time's six levels, fastest first.
func (d Data) LeadTimeScores() []string {
	return bandScores(metrics.LessThanOneHour, metrics.MoreThanSixMonths)
}
