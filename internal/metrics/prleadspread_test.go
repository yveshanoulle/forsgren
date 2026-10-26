package metrics

import (
	"testing"
	"time"
)

// TestPRLeadTimeMedianAndP90 (forsgren#423, Yves on #432): the pull
// request lead time has a median from two pull requests (the mean of the two
// middle ones for an even count) and a 90th percentile by nearest rank from
// ten, as the other spreads have; below that they are zero and not shown.
func TestPRLeadTimeMedianAndP90(t *testing.T) {
	h := time.Hour
	cases := map[string]struct {
		hours             []int
		median, p90       time.Duration
		hasMedian, hasP90 bool
	}{
		"none":     {nil, 0, 0, false, false},
		"one":      {[]int{5}, 0, 0, false, false},
		"two":      {[]int{1, 4}, 150 * time.Minute, 0, true, false},
		"three":    {[]int{9, 1, 3}, 3 * h, 0, true, false},
		"nine":     {[]int{1, 2, 3, 4, 5, 6, 7, 8, 9}, 5 * h, 0, true, false},
		"ten":      {[]int{10, 9, 8, 7, 6, 5, 4, 3, 2, 1}, 5*h + 30*time.Minute, 9 * h, true, true},
		"eleven":   {[]int{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11}, 6 * h, 10 * h, true, true},
		"unsorted": {[]int{30, 1, 2, 3, 4, 5, 6, 7, 8, 9}, 5*h + 30*time.Minute, 9 * h, true, true},
	}
	for name, c := range cases {
		got := shopPRLead(shopPulls(c.hours...)...)
		if got.Median != c.median || got.HasMedian() != c.hasMedian {
			t.Errorf("%s: want median %v (%t), got %v (%t)", name, c.median, c.hasMedian, got.Median, got.HasMedian())
		}
		if got.P90 != c.p90 || got.HasP90() != c.hasP90 {
			t.Errorf("%s: want p90 %v (%t), got %v (%t)", name, c.p90, c.hasP90, got.P90, got.HasP90())
		}
	}
}

// TestPRLeadTimeCellsShowMeanMedianAndP90 (forsgren#423): the cells are
// the three figures like the other groups, a dash while one is not shown; the
// mean carries the notes, and the median alone carries them in the table that
// shows the median only (MedianNotedCell); the count, the cut count and the
// share are not in a cell any more.
func TestPRLeadTimeCellsShowMeanMedianAndP90(t *testing.T) {
	h := time.Hour
	cases := map[string]struct {
		lead              PRLeadTime
		mean, median, p90 string
		notes             []Note
	}{
		"none": {PRLeadTime{}, "-", "-", "-", nil},
		"one, cut": {PRLeadTime{PullRequests: 1, Mean: 5 * h, Cut: 1}, "5 h", "-", "-",
			[]Note{{NoteLowerBound, 1, 0}}},
		"two": {PRLeadTime{PullRequests: 2, Mean: 2 * h, Median: 2 * h}, "2 h", "2 h", "-", nil},
		"ten, bots": {PRLeadTime{PullRequests: 10, Mean: 3 * h, Median: 2 * h, P90: 9 * h, Bots: 3},
			"3 h", "2 h", "9 h", []Note{{NoteBotsNotCounted, 3, 0}}},
		"no human, bots": {PRLeadTime{Bots: 2}, "-", "-", "-", []Note{{NoteBotsNotCounted, 2, 0}}},
		"all three kinds": {PRLeadTime{PullRequests: 3, Mean: h, Median: h, Cut: 1, CreatedStandsIn: 2, Bots: 3},
			"1 h", "1 h", "-", []Note{{NoteLowerBound, 1, 0}, {NoteCreatedTime, 2, 0}, {NoteBotsNotCounted, 3, 0}}},
	}
	for name, c := range cases {
		l := c.lead
		if got := [3]string{l.MeanCell().Value, l.MedianCell(), l.P90Cell()}; got != [3]string{c.mean, c.median, c.p90} {
			t.Errorf("%s: want %q, %q, %q, got %q", name, c.mean, c.median, c.p90, got)
		}
		if got := l.MedianNotedCell(); got.Value != c.median || !sameNotes(got.Notes, c.notes) {
			t.Errorf("%s: want the median cell %q with %v, got %+v", name, c.median, c.notes, got)
		}
		if got := l.MeanCell().Notes; !sameNotes(got, c.notes) {
			t.Errorf("%s: want the mean cell's notes %v, got %v", name, c.notes, got)
		}
	}
}

// sameNotes says whether two lists of notes are the same, nil being empty.
func sameNotes(a, b []Note) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// TestPRLeadTimeStateIsNotReadable (forsgren#423): a project whose
// pull request read was refused has the state sentence in place of the cells,
// and any other project has no state.
func TestPRLeadTimeStateIsNotReadable(t *testing.T) {
	refused := PRLeadTime{NotReadable: true, PullRequests: 2, Mean: time.Hour, Bots: 2}
	if got := refused.State(); got != "Pull requests not readable" {
		t.Errorf("want the state %q, got %q", "Pull requests not readable", got)
	}
	if got := (PRLeadTime{PullRequests: 2}).State(); got != "" {
		t.Errorf("want no state, got %q", got)
	}
}

// TestMainlineIntervalMedianNotedCellCarriesTheNotes (forsgren#423): in the
// table that shows the median only the note on the commits timed by author
// date sits on the median cell, a dash below two gaps with the note when there
// is a gap, none without one.
func TestMainlineIntervalMedianNotedCellCarriesTheNotes(t *testing.T) {
	h := time.Hour
	cases := map[string]struct {
		in    MainlineInterval
		value string
		notes []Note
	}{
		"no commit":      {MainlineInterval{}, "-", nil},
		"no gap, a note": {MainlineInterval{Commits: 1, ByAuthorDate: 1}, "-", nil},
		"one gap, a note": {MainlineInterval{Commits: 2, Gaps: 1, Mean: h, ByAuthorDate: 2}, "-",
			[]Note{{NoteMostlyEstimated, 2, 2}}},
		"three gaps, some": {MainlineInterval{Commits: 4, Gaps: 3, Mean: h, Median: 2 * h, ByAuthorDate: 2}, "2 h",
			[]Note{{NoteByAuthorDate, 2, 0}}},
		"three gaps, none": {MainlineInterval{Commits: 4, Gaps: 3, Mean: h, Median: 2 * h}, "2 h", nil},
	}
	for name, c := range cases {
		got := c.in.MedianNotedCell()
		if got.Value != c.value || !sameNotes(got.Notes, c.notes) {
			t.Errorf("%s: want %q with %v, got %+v", name, c.value, c.notes, got)
		}
	}
}
