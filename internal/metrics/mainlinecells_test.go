package metrics

import (
	"strings"
	"testing"
	"time"
)

// intervalCells are the three cells of the Mainline Interval group of the TBD
// page that shows all the figures, mean, median and p90 (forsgren#387, step 1;
// forsgren#423), parted by " | " for a test to compare in one string.
func intervalCells(m MainlineInterval) string {
	return strings.Join([]string{m.MeanCell().Value, m.MedianCell(), m.P90Cell()}, " | ")
}

// TestMainlineIntervalCells (forsgren#387, step 1, decisions #388 and #389;
// forsgren#423, decision #424 C): the group is three columns of one number
// each, the mean, the median and the 90th percentile; the deviation and the
// number of gaps are not cells any more; a figure that is not shown yet is a
// dash in its own cell, a project without a gap a dash in all three, and the
// note on the commits timed by author date is on the mean cell (forsgren#394,
// step 2).
func TestMainlineIntervalCells(t *testing.T) {
	h := time.Hour
	cases := map[string]struct {
		in   MainlineInterval
		want string
	}{
		"no commit":  {MainlineInterval{}, "- | - | -"},
		"one commit": {MainlineInterval{Commits: 1}, "- | - | -"},
		"one gap":    {MainlineInterval{Commits: 2, Gaps: 1, Mean: 2 * h}, "2 h | - | -"},
		"two gaps":   {MainlineInterval{Commits: 3, Gaps: 2, Mean: 2 * h, Median: 2 * h}, "2 h | 2 h | -"},
		"ten gaps": {MainlineInterval{Commits: 11, Gaps: 10, Mean: 27 * time.Minute,
			Median: 7 * time.Minute, P90: 45 * time.Minute}, "27 m | 7 m | 45 m"},
		"some by author date": {MainlineInterval{Commits: 4, Gaps: 3, Mean: h, Median: h, ByAuthorDate: 2},
			"1 h | 1 h | -"},
		"mostly by author date": {MainlineInterval{Commits: 3, Gaps: 2, Mean: h, Median: h, ByAuthorDate: 3},
			"1 h | 1 h | -"},
		"no gap, a note": {MainlineInterval{Commits: 1, ByAuthorDate: 1}, "- | - | -"},
	}
	for name, c := range cases {
		if got := intervalCells(c.in); got != c.want {
			t.Errorf("%s: want %q, got %q", name, c.want, got)
		}
	}
}
