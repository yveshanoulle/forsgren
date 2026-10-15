package page

// The scores of the levels the legend lists (forsgren#79): each comes from
// the function the scoring view scores with, so the legend cannot drift from
// the scoring view.

import "github.com/yveshanoulle/forsgren/internal/metrics"

// LeadTimeScores are the scores of lead time's six levels, fastest first, as
// the scoring view gives them.
func (d Data) LeadTimeScores() []string {
	var scores []string
	for b := metrics.LessThanOneHour; b <= metrics.MoreThanSixMonths; b++ {
		scores = append(scores, scoreCell(metrics.BandScore(b)))
	}
	return scores
}
