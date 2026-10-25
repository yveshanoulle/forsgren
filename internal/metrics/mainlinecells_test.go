package metrics

import (
	"strings"
	"testing"
	"time"
)

// intervalCells are the five cells of the Mainline Interval group of the TBD
// page (forsgren#387, step 1), mean, deviation, median, p90 and gaps, parted
// by " | " for a test to compare in one string.
func intervalCells(m MainlineInterval) string {
	return strings.Join([]string{m.MeanCell(), m.DeviationCell(), m.MedianCell(), m.P90Cell(), m.GapsCell()}, " | ")
}

// TestMainlineIntervalCells (forsgren#387, step 1, decisions #388 and #389):
// the group is five columns of one number each, the mean, the sample standard
// deviation, the median, the 90th percentile and the number of gaps they rest
// on; a figure that is not shown yet is a dash in its own cell, a project
// without a gap a dash in all five, and the note on the commits timed by
// author date ends the gaps cell, as the other groups end their last cell.
func TestMainlineIntervalCells(t *testing.T) {
	h := time.Hour
	cases := map[string]struct {
		in   MainlineInterval
		want string
	}{
		"no commit":  {MainlineInterval{}, "- | - | - | - | -"},
		"one commit": {MainlineInterval{Commits: 1}, "- | - | - | - | -"},
		"one gap":    {MainlineInterval{Commits: 2, Gaps: 1, Mean: 2 * h}, "2 h | - | - | - | 1"},
		"two gaps": {MainlineInterval{Commits: 3, Gaps: 2, Mean: 2 * h, Deviation: h, Median: 2 * h},
			"2 h | 1 h | 2 h | - | 2"},
		"ten gaps": {MainlineInterval{Commits: 11, Gaps: 10, Mean: 27 * time.Minute, Deviation: 2*h + 19*time.Minute,
			Median: 7 * time.Minute, P90: 45 * time.Minute}, "27 m | 2 h 19 | 7 m | 45 m | 10"},
		"a big count": {MainlineInterval{Commits: 1163, Gaps: 1162, Mean: h, Deviation: h, Median: h, P90: h},
			"1 h | 1 h | 1 h | 1 h | 1162"},
		"some by author date": {MainlineInterval{Commits: 4, Gaps: 3, Mean: h, Deviation: h, Median: h, ByAuthorDate: 2},
			"1 h | 1 h | 1 h | - | 3 · 2 commits timed by author date"},
		"mostly by author date": {MainlineInterval{Commits: 3, Gaps: 2, Mean: h, Deviation: h, Median: h, ByAuthorDate: 3},
			"1 h | 1 h | 1 h | - | 2 · Mostly estimated: 3 of 3 commits timed by author date."},
		"no gap, a note": {MainlineInterval{Commits: 1, ByAuthorDate: 1}, "- | - | - | - | -"},
	}
	for name, c := range cases {
		if got := intervalCells(c.in); got != c.want {
			t.Errorf("%s: want %q, got %q", name, c.want, got)
		}
	}
}
