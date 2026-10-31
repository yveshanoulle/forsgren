package metrics

import (
	"math"
	"testing"
	"time"
)

// The standard deviation of every TBD measure (forsgren#588, step 2, decision
// #599 A): the fourth figure of tbd_figures: all, the sample standard
// deviation, shown from two values like the median.

// TestDeviationIsTheSampleStandardDeviation: the squares of the differences
// from the mean over n-1, not n, worked out by hand: 1 and 3 have the mean 2
// and the squares 1 and 1, so the root of 2 (over n it would be 1); 2, 4, 4,
// 4, 5, 5, 7 and 9 have the mean 5 and the squares 32, so the root of 32/7
// (over n it would be 2); below two values there is none.
func TestDeviationIsTheSampleStandardDeviation(t *testing.T) {
	for _, c := range []struct {
		values []float64
		want   float64
	}{
		{nil, 0},
		{[]float64{5}, 0},
		{[]float64{1, 3}, math.Sqrt(2)},
		{[]float64{2, 4, 4, 4, 5, 5, 7, 9}, math.Sqrt(32.0 / 7)},
		{[]float64{6, 6, 6}, 0},
	} {
		if got := deviationOf(c.values); math.Abs(got-c.want) > 1e-12 {
			t.Errorf("%v: want %v, got %v", c.values, c.want, got)
		}
	}
}

// rootOf is the root of variance times unit, to the nanosecond: the sample
// standard deviation of times whose squared differences from their mean, over
// n-1, add up to variance units squared (1 and 3 hours: rootOf(2, time.Hour)).
func rootOf(variance float64, unit time.Duration) time.Duration {
	return time.Duration(math.Round(math.Sqrt(variance) * float64(unit)))
}

// deviationCells are a measure's deviation cell over values, built by the
// measure's own calculation: the gaps in hours of a Mainline Interval, the
// lead times in hours of a PR Lead Time, times in hours of a DurationSpread,
// counts of a CountSpread.
var deviationCells = map[string]func(values ...int) string{
	"Mainline Interval": func(v ...int) string { return mainlineOf(shopGaps(v...)).DeviationCell() },
	"PR Lead Time":      func(v ...int) string { return shopPRLead(shopPulls(v...)...).DeviationCell() },
	"duration spread": func(v ...int) string {
		return durationSpreadOf(scaledBy(time.Hour, v)).DeviationCell()
	},
	"count spread": func(v ...int) string { return countSpreadOf(scaledBy(1, v)).DeviationCell() },
}

// scaledBy are values times unit, as floats.
func scaledBy(unit time.Duration, values []int) []float64 {
	out := make([]float64, len(values))
	for i, v := range values {
		out[i] = float64(time.Duration(v) * unit)
	}
	return out
}

// TestEveryMeasureShowsItsDeviationFromTwoValues: 1, 2 and 3 have the sample
// standard deviation 1 (over n it would be 49 minutes, 0.82); two equal values
// have a deviation of 0, shown, and one value has none, a dash, whatever its
// size: the median's rule.
func TestEveryMeasureShowsItsDeviationFromTwoValues(t *testing.T) {
	for name, cellOf := range deviationCells {
		one, zero := "1 h", "< 1 m"
		if name == "count spread" {
			one, zero = dec("1.0"), dec("0.0")
		}
		for _, c := range []struct {
			values []int
			want   string
		}{{[]int{1, 2, 3}, one}, {[]int{3, 1, 2}, one}, {[]int{2, 2}, zero}, {[]int{5}, "-"}, {nil, "-"}} {
			if got := cellOf(c.values...); got != c.want {
				t.Errorf("%s over %v: want %q, got %q", name, c.values, c.want, got)
			}
		}
	}
}
