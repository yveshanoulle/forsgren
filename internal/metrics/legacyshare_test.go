package metrics

import (
	"reflect"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// The TBD page names the old data plainly once it is most of a figure
// (forsgren#345, step 3, Yves's answer on #344): more than half, never at half
// or below, where the cell keeps its plain note. The Mainline Interval's note
// is about how accurately the commits are timed, so it says "estimated"; the
// Developers' note is about the authors not known, never an estimate.

// TestMainlineIntervalSaysMostlyEstimatedAboveHalf (forsgren#345, step 3;
// forsgren#394, step 2): when more than half of the commits counted are timed
// by author date, the note is kind 1 with the commits it is part of; at half
// and below it is kind 2, the plain count; none without one.
func TestMainlineIntervalSaysMostlyEstimatedAboveHalf(t *testing.T) {
	for _, c := range []struct {
		commits, byAuthor int
		want              []Note
	}{
		{1134, 1121, []Note{{NoteMostlyEstimated, 1121, 1134}}},
		{5, 3, []Note{{NoteMostlyEstimated, 3, 5}}},
		{3, 3, []Note{{NoteMostlyEstimated, 3, 3}}},
		{4, 2, []Note{{NoteByAuthorDate, 2, 0}}},
		{2, 1, []Note{{NoteByAuthorDate, 1, 0}}},
		{5, 2, []Note{{NoteByAuthorDate, 2, 0}}},
		{4, 0, nil},
	} {
		got := MainlineInterval{Commits: c.commits, ByAuthorDate: c.byAuthor}
		if !reflect.DeepEqual(got.Notes(), c.want) {
			t.Errorf("%d of %d by author date: want the notes %v, got %v", c.byAuthor, c.commits, c.want, got.Notes())
		}
	}
}

// TestMainlineIntervalMeanCellCarriesTheNote (forsgren#394, step 2): the note
// is on the mean cell, so the gaps can leave the table (forsgren#423) without
// losing it; the gaps cell is the number alone; a project without a gap has a
// dash and no note.
func TestMainlineIntervalMeanCellCarriesTheNote(t *testing.T) {
	got := MainlineInterval{
		Commits: 3, Gaps: 2, Mean: 2 * time.Hour, Deviation: time.Hour, Median: time.Hour, ByAuthorDate: 2,
	}
	if want := (NotedCell{"2 h", []Note{{NoteMostlyEstimated, 2, 3}}}); !reflect.DeepEqual(got.MeanCell(), want) {
		t.Errorf("want the mean cell %v, got %v", want, got.MeanCell())
	}
	if got.GapsCell() != "2" {
		t.Errorf("want the gaps cell 2, got %q", got.GapsCell())
	}
	if none := (MainlineInterval{Commits: 1, ByAuthorDate: 1}).MeanCell(); none.Value != "-" || len(none.Notes) != 0 {
		t.Errorf("want a dash and no note without a gap, got %v", none)
	}
}

// legacyBy is by's commit as the commits formats v1 and v2 stored it: no
// parents and no committer date, so stored before forsgren kept them.
func legacyBy(login, sha string) history.Commit {
	c := by(login, sha)
	c.Parents, c.CommittedAt = nil, time.Time{}
	return c
}
