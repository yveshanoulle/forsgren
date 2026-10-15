package page

// The scores of the levels the legend lists (forsgren#79): each comes from
// the function the scoring view scores with, so the legend cannot drift from
// the scoring view. Every metric has six levels; levelScores lists the score
// of each, from the first level to the last, with the score of one level as
// the metric scores it: one number per band (bandScore), or the range of a
// percent band (percentRange).

import (
	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// levelScores are the scores of the levels from first to last, each as score
// gives it.
func levelScores[B ~int](first, last B, score func(B) string) []string {
	var scores []string
	for b := first; b <= last; b++ {
		scores = append(scores, score(b))
	}
	return scores
}

// bandScore is the score of a band the scoring view scores as a whole
// (metrics.BandScore).
func bandScore[B ~int](b B) string { return scoreCell(metrics.BandScore(b)) }

// percentRange is the score of a percent band. The scoring view scores the
// whole percent (metrics.PercentScore), so a band has the scores of its
// lowest and of its highest percent: "9 to 7.1", or one number when they are
// equal (decision #197).
func percentRange(b metrics.ChangeFailBand) string {
	lowest, highest := b.Percents()
	best, worst := scoreCell(metrics.PercentScore(lowest)), scoreCell(metrics.PercentScore(highest))
	if best != worst {
		best += " to " + worst
	}
	return best
}

// FrequencyScores are the scores of deployment frequency's six levels,
// fastest first.
func (d Data) FrequencyScores() []string {
	return levelScores(metrics.OnDemand, metrics.LessThanSixMonthly, bandScore)
}

// LeadTimeScores are the scores of lead time's six levels, fastest first.
func (d Data) LeadTimeScores() []string {
	return levelScores(metrics.LessThanOneHour, metrics.MoreThanSixMonths, bandScore)
}

// ChangeFailScores are the score ranges of change fail rate's six levels,
// lowest rate first.
func (d Data) ChangeFailScores() []string {
	return levelScores(metrics.ZeroPercent, metrics.HundredPercent, percentRange)
}

// RecoveryScores are the scores of failed deployment recovery time's six
// levels, fastest first. The scoring view scores a recovery with
// metrics.BandScore of its LeadTimeBand (Row.scores), the type of lead time's
// bands, so these are lead time's scores.
func (d Data) RecoveryScores() []string { return d.LeadTimeScores() }

// ReworkScores are the score ranges of deployment rework rate's six levels,
// lowest rate first. The scoring view scores a rework rate with
// metrics.PercentScore (Row.scores), as it does a change fail rate, and the
// six levels are the same, so these are change fail rate's score ranges.
func (d Data) ReworkScores() []string { return d.ChangeFailScores() }
