package metrics

import (
	"math"
	"time"
)

// A spread is the mean, the median, the 90th percentile and the standard
// deviation of a set of numbers, with how many there are (forsgren#397, step
// 4; the deviation forsgren#588, step 2): the figures of the TBD page's push
// and deployment measures, labelled like the Mainline Interval's. The median
// and the sample standard deviation (deviationOf) are shown from two numbers
// and the 90th percentile from minP90Gaps, by medianAndP90's rules (nearest
// rank, the mean of the two middle ones for an even count); a figure that is
// not shown is zero.

// DurationSpread is the spread of a set of times.
type DurationSpread struct {
	Count                        int
	Mean, Median, P90, Deviation time.Duration
}

// HasMedian says whether the median is shown: it needs two times.
func (s DurationSpread) HasMedian() bool { return s.Count > 1 }

// HasP90 says whether the 90th percentile is shown: it needs minP90Gaps times.
func (s DurationSpread) HasP90() bool { return s.Count >= minP90Gaps }

// CountSpread is the spread of a set of counts.
type CountSpread struct {
	Count                        int
	Mean, Median, P90, Deviation float64
}

// HasMedian says whether the median is shown: it needs two counts.
func (s CountSpread) HasMedian() bool { return s.Count > 1 }

// HasP90 says whether the 90th percentile is shown: it needs minP90Gaps counts.
func (s CountSpread) HasP90() bool { return s.Count >= minP90Gaps }

// durationSpreadOf is the spread of times in nanoseconds; the zero spread for
// none.
func durationSpreadOf(nanoseconds []float64) DurationSpread {
	if len(nanoseconds) == 0 {
		return DurationSpread{}
	}
	median, p90 := medianAndP90(nanoseconds)
	return DurationSpread{Count: len(nanoseconds), Mean: time.Duration(math.Round(meanOf(nanoseconds))),
		Median: median, P90: p90, Deviation: durationDeviationOf(nanoseconds)}
}

// countSpreadOf is the spread of counts; the zero spread for none. A count is
// carried as that many seconds through medianAndP90, which then applies its
// rules to counts too, without rounding a median of x.5.
func countSpreadOf(counts []float64) CountSpread {
	if len(counts) == 0 {
		return CountSpread{}
	}
	scaled := make([]float64, len(counts))
	for i, c := range counts {
		scaled[i] = c * float64(time.Second)
	}
	median, p90 := medianAndP90(scaled)
	return CountSpread{Count: len(counts), Mean: meanOf(counts), Median: median.Seconds(), P90: p90.Seconds(),
		Deviation: deviationOf(counts)}
}
