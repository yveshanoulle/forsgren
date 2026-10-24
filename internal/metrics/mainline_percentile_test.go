package metrics

import (
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// shopGaps are commits of acme/app whose consecutive author dates are the
// given gaps in hours apart, the first 100 hours before now, stored newest
// first (the order the metric must not depend on).
func shopGaps(gapHours ...int) []history.Commit {
	total := 100
	times := []int{total}
	for _, g := range gapHours {
		total -= g
		times = append(times, total)
	}
	commits := make([]history.Commit, len(times))
	for i, ago := range times {
		commits[len(times)-1-i] = shopAuthored("g"+string(rune('a'+i)), time.Duration(ago)*time.Hour)
	}
	return commits
}

// gapSpread is the part of a MainlineInterval the percentile tests compare: the
// gaps, the median and the 90th percentile, the last zero while not shown.
type gapSpread struct {
	Gaps        int
	Median, P90 time.Duration
}

// gapSpreadOf is the spread of m.
func gapSpreadOf(m MainlineInterval) gapSpread { return gapSpread{m.Gaps, m.Median, m.P90} }

// TestMainlineIntervalMedianAndNinetiethPercentile (forsgren#272): the median
// is the middle gap, or the mean of the two middle ones; the 90th percentile
// is the nearest rank, the gap at position ceil(0.9 n) of the gaps sorted from
// the shortest. The expected values are worked out by hand:
//   - 1..10 hours: n = 10, median (5+6)/2 = 5.5 h, rank ceil(9) = 9, so 9 h;
//   - 1..11 hours: n = 11, median 6 h, rank ceil(9.9) = 10, so 10 h;
//   - nine gaps of 1 h and one of 91 h: median 1 h, rank 9, so 1 h, while the
//     mean is 10 h: the long gap is in the mean and the deviation, not in p90;
//   - 1 and 3 hours: median 2 h, under ten gaps there is no p90.
func TestMainlineIntervalMedianAndNinetiethPercentile(t *testing.T) {
	h := time.Hour
	cases := []struct {
		name    string
		gaps    []int
		want    gapSpread
		cellEnd string
	}{
		{"1 to 10 hours", []int{7, 3, 10, 1, 9, 2, 8, 4, 6, 5}, gapSpread{10, 5*h + 30*time.Minute, 9 * h},
			"5 h 30 min | 9 h"},
		{"1 to 11 hours", []int{11, 1, 5, 2, 10, 3, 9, 4, 8, 6, 7}, gapSpread{11, 6 * h, 10 * h}, "6 h | 10 h"},
		{"one long gap", []int{1, 1, 1, 91, 1, 1, 1, 1, 1, 1}, gapSpread{10, h, h}, "1 h | 1 h"},
		{"two gaps", []int{3, 1}, gapSpread{2, 2 * h, 0}, "2 h | -"},
		{"nine gaps", []int{1, 2, 3, 4, 5, 6, 7, 8, 9}, gapSpread{9, 5 * h, 0}, "5 h | -"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := mainlineOf(shopGaps(c.gaps...)...)
			if gapSpreadOf(got) != c.want {
				t.Errorf("want %+v, got %+v", c.want, gapSpreadOf(got))
			}
			if cells := got.MedianCell() + " | " + got.P90Cell(); cells != c.cellEnd {
				t.Errorf("want the median and p90 cells %q, got %q", c.cellEnd, cells)
			}
		})
	}
}

// TestMainlineIntervalShowsMedianFromTwoGapsAndP90FromTen (forsgren#272): the
// minimums, one gap is its own mean and has neither, nine gaps have a median
// and no p90.
func TestMainlineIntervalShowsMedianFromTwoGapsAndP90FromTen(t *testing.T) {
	for gaps, want := range map[int][2]bool{1: {false, false}, 2: {true, false}, 9: {true, false}, 10: {true, true}} {
		ones := make([]int, gaps)
		for i := range ones {
			ones[i] = 1
		}
		got := mainlineOf(shopGaps(ones...)...)
		if [2]bool{got.HasMedian(), got.HasP90()} != want {
			t.Errorf("%d gaps: want median and p90 shown %v, got %+v", gaps, want, got)
		}
	}
}
