package page

// The scores of the levels the legend lists (forsgren#79): each comes from
// the function the scoring view scores with, so the legend cannot drift from
// the scoring view.

import (
	"github.com/yveshanoulle/forsgren/internal/metrics"
)

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

// ChangeFailScores are the scores of change fail rate's six levels, lowest
// rate first. The scoring view scores the whole percent, so a level has the
// scores of its lowest and of its highest percent: "9 to 7.1", or one number
// when they are equal (forsgren#79).
func (d Data) ChangeFailScores() []string {
	var scores []string
	for b := metrics.ZeroPercent; b <= metrics.HundredPercent; b++ {
		lowest, highest := b.Percents()
		best, worst := scoreCell(metrics.PercentScore(lowest)), scoreCell(metrics.PercentScore(highest))
		if best != worst {
			best += " to " + worst
		}
		scores = append(scores, best)
	}
	return scores
}

// RecoveryScores are the scores of failed deployment recovery time's six
// levels, fastest first. The scoring view scores a recovery with
// metrics.BandScore of its LeadTimeBand (Row.scores), the type of lead time's
// bands, so these are lead time's scores.
func (d Data) RecoveryScores() []string { return d.LeadTimeScores() }
