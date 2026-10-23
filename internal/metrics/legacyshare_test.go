package metrics

import (
	"strings"
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
	want := "2 h ± 1 h (2) · median 1 h · p90 - · Mostly estimated: 2 of 3 commits timed by author date."
	if got.Cell() != want {
		t.Errorf("want the cell %q, got %q", want, got.Cell())
	}
}

// legacyBy is by's commit as the commits formats v1 and v2 stored it: no
// parents and no committer date, so stored before forsgren kept them.
func legacyBy(login, sha string) history.Commit {
	c := by(login, sha)
	c.Parents, c.CommittedAt = nil, time.Time{}
	return c
}

// TestDevelopersCountTheCommitsAndTheLegacyUnknownOnes (forsgren#345, step
// 3): the Developers hold how many distinct commits were deployed in the
// window, bots' included, and how many of those without a known author are
// legacy data: stored before the commits format v3, with neither parents nor
// a committer date. A commit stored with its lineage and no author, GitHub
// linking it to no account, is unknown but not legacy data.
func TestDevelopersCountTheCommitsAndTheLegacyUnknownOnes(t *testing.T) {
	commits := []history.Commit{
		legacyBy("", "a1"), legacyBy("", "a2"), by("", "a3"), legacyBy("octo-dev", "a4"),
		by("dependabot[bot]", "a5"), legacyBy("", "a1"),
	}
	want := Developers{Project: "Acme Shop", Count: 1, Unknown: 3, Legacy: 2, Commits: 5}
	if got := shopDevelopers(commits...); got != want {
		t.Errorf("want %+v, got %+v", want, got)
	}
}

// TestDevelopersCellNamesTheLegacyDataAboveHalf (forsgren#345, step 3): when
// the legacy commits without a known author are more than half of the
// deployed commits, the cell is Yves's sentence, the count named in
// developers and the commits excluded; the commits without a known author
// that are not legacy data are not called so. At half or below, or when the
// unknown ones are most of the commits but the legacy ones are not, the cell
// keeps its plain note.
func TestDevelopersCellNamesTheLegacyDataAboveHalf(t *testing.T) {
	for _, c := range []struct {
		in   Developers
		want string
	}{
		{Developers{Count: 3, Unknown: 1099, Legacy: 1099, Commits: 1134},
			"3 developers · 1099 commits without a known author excluded (legacy data)."},
		{Developers{Count: 1, Unknown: 3, Legacy: 3, Commits: 5},
			"1 developer · 3 commits without a known author excluded (legacy data)."},
		{Developers{Count: 0, Unknown: 1, Legacy: 1, Commits: 1},
			"0 developers · 1 commit without a known author excluded (legacy data)."},
		{Developers{Count: 2, Unknown: 5, Legacy: 3, Commits: 5},
			"2 developers · 5 commits without a known author excluded (3 of them legacy data)."},
		{Developers{Count: 1, Unknown: 2, Legacy: 2, Commits: 4}, "1 · 2 commits without a known author are not counted"},
		{Developers{Count: 1, Unknown: 3, Legacy: 1, Commits: 4}, "1 · 3 commits without a known author are not counted"},
		{Developers{Count: 3, Commits: 3}, "3"},
	} {
		got := c.in.Cell()
		if got != c.want {
			t.Errorf("%+v: want the cell %q, got %q", c.in, c.want, got)
		}
		if strings.Contains(strings.ToLower(got), "estimat") {
			t.Errorf("%+v: the Developers cell is about attribution, never an estimate: %q", c.in, got)
		}
	}
}
