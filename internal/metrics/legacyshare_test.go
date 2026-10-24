package metrics

import (
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// The TBD page names the old data plainly once it is most of a figure
// (forsgren#345, step 3, Yves's answer on #344): more than half, never at half
// or below, where the cell keeps its plain note. The Mainline Interval's note
// is about how accurately the commits are timed, so it says "estimated"; the
// Developers' note is about the authors not known, never an estimate.

// TestMainlineIntervalSaysMostlyEstimatedAboveHalf (forsgren#345, step 3):
// when more than half of the commits counted are timed by author date, the
// note is Yves's sentence, the count of the commits counted in it; at half
// and below it is the plain count, as before.
func TestMainlineIntervalSaysMostlyEstimatedAboveHalf(t *testing.T) {
	for _, c := range []struct {
		commits, byAuthor int
		want              string
	}{
		{1134, 1121, "Mostly estimated: 1121 of 1134 commits timed by author date."},
		{5, 3, "Mostly estimated: 3 of 5 commits timed by author date."},
		{3, 3, "Mostly estimated: 3 of 3 commits timed by author date."},
		{4, 2, "2 commits timed by author date"},
		{2, 1, "1 commit timed by author date"},
		{5, 2, "2 commits timed by author date"},
		{4, 0, ""},
	} {
		got := MainlineInterval{Commits: c.commits, ByAuthorDate: c.byAuthor}
		if got.Note() != c.want {
			t.Errorf("%d of %d by author date: want the note %q, got %q", c.byAuthor, c.commits, c.want, got.Note())
		}
	}
}

// TestMainlineIntervalCellSaysMostlyEstimated (forsgren#345, step 3): the
// sentence takes the plain note's place in the cell, after the separator.
func TestMainlineIntervalCellSaysMostlyEstimated(t *testing.T) {
	got := MainlineInterval{
		Commits: 3, Gaps: 2, Mean: 2 * time.Hour, Deviation: time.Hour, Median: time.Hour, ByAuthorDate: 2,
	}
	want := "2 · Mostly estimated: 2 of 3 commits timed by author date."
	if got.GapsCell() != want {
		t.Errorf("want the cell %q, got %q", want, got.GapsCell())
	}
}

// legacyBy is by's commit as the commits formats v1 and v2 stored it: no
// parents and no committer date, so stored before forsgren kept them.
func legacyBy(login, sha string) history.Commit {
	c := by(login, sha)
	c.Parents, c.CommittedAt = nil, time.Time{}
	return c
}
