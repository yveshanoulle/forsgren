package metrics

// The standard deviation of every spread of the TBD page (forsgren#588, step
// 2, Yves's ruling on #588, decision #599 A): the fourth figure of
// tbd_figures: all, after the p90, for the Mainline Interval and every other
// measure alike.
//
// It is the sample standard deviation, the sum of the squares of the
// differences from the mean over n-1. The book (Steve Smith, Measuring
// Continuous Delivery) reads the Mainline Interval as a median and a standard
// deviation of the intervals of a period to say how a team integrates: the
// gaps of one window are a sample of that, not the whole of it, and the
// sample deviation is the estimate for a sample. It is also the deviation
// forsgren showed for the interval before forsgren#423 (decision #270). Over
// n-1 it needs two values, the median's rule, so it is shown from two values
// and is a dash below that.

import (
	"math"
	"time"
)

// deviationOf is the sample standard deviation of values; zero below two.
func deviationOf(values []float64) float64 {
	if len(values) < 2 {
		return 0
	}
	mean, squares := meanOf(values), 0.0
	for _, v := range values {
		squares += (v - mean) * (v - mean)
	}
	return math.Sqrt(squares / float64(len(values)-1))
}

// durationDeviationOf is the sample standard deviation of times in
// nanoseconds, to the nanosecond.
func durationDeviationOf(nanoseconds []float64) time.Duration {
	return time.Duration(math.Round(deviationOf(nanoseconds)))
}

// DeviationCell is the sample standard deviation of the gaps; "-" below two
// gaps.
func (m MainlineInterval) DeviationCell() string { return m.shown(m.HasMedian(), m.Deviation) }

// DeviationCell is the sample standard deviation of the lead times, a dash
// below two pull requests.
func (m PRLeadTime) DeviationCell() string { return m.shown(m.HasMedian(), m.Deviation) }

// DeviationCell is the sample standard deviation of the times, a dash below
// two times.
func (s DurationSpread) DeviationCell() string { return s.cell(s.HasMedian(), s.Deviation) }

// DeviationCell is the sample standard deviation of the counts, a dash below
// two counts.
func (s CountSpread) DeviationCell() string { return s.cell(s.HasMedian(), s.Deviation) }
