package metrics

import (
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// hoursAgo are a commit's author and committer dates, in hours before now; a
// committed of -1 is no committer date.
type hoursAgo struct{ authored, committed int }

// lined is a commit of acme/app in the deployment id, deployed an hour ago,
// authored and committed ago, with parents, the first parent first.
func lined(id int64, sha string, ago hoursAgo, parents ...string) history.Commit {
	c := history.Commit{
		Repository: "acme/app", Kind: history.KindEnvironment, DeploymentID: id, SHA: sha,
		AuthoredAt: now.Add(-time.Duration(ago.authored) * time.Hour), DeployedAt: now.Add(-time.Hour),
		Parents: parents,
	}
	if ago.committed >= 0 {
		c.CommittedAt = now.Add(-time.Duration(ago.committed) * time.Hour)
	}
	return c
}

// placing is the part of a MainlineInterval the lineage tests compare: the
// commits counted, the gaps, the mean gap and how many are placed by author
// date.
type placing struct {
	Commits, Gaps int
	Mean          time.Duration
	ByAuthorDate  int
}

// placingOf is the placing of m.
func placingOf(m MainlineInterval) placing {
	return placing{m.Commits, m.Gaps, m.Mean, m.ByAuthorDate}
}

// mergedDeployment is the commits of one deployment of acme/app, as a
// comparison with the deployment before it gives them: the mainline m1, a
// branch b1 and b2 made from the same base, the merge m2 (first parent m1,
// second b2) and the tip m3. The first-parent chain is m3, m2, m1, committed
// 10, 20 and 40 hours ago: gaps of 20 and 10 hours, a mean of 15 hours. By
// author date (50, 30 and 12 hours ago) the mean would be 19 hours.
func mergedDeployment() []history.Commit {
	return []history.Commit{
		lined(1, "m1", hoursAgo{50, 40}, "base"),
		lined(1, "b1", hoursAgo{48, 47}, "base"),
		lined(1, "b2", hoursAgo{46, 45}, "b1"),
		lined(1, "m2", hoursAgo{30, 20}, "m1", "b2"),
		lined(1, "m3", hoursAgo{12, 10}, "m2"),
	}
}

// TestMainlineIntervalLeavesOutTheCommitsAMergeBroughtIn (forsgren#254, step
// 4): of a deployment's commits, only those on the first-parent chain from its
// tip count; b1 and b2, the branch m2 merged, do not. Following the second
// parent would count m3, m2, b2 and b1.
func TestMainlineIntervalLeavesOutTheCommitsAMergeBroughtIn(t *testing.T) {
	got := mainlineOf(mergedDeployment()...)
	if got.Commits != 3 {
		t.Errorf("want the 3 first-parent commits m1, m2 and m3, got %+v", got)
	}
}

// TestMainlineIntervalPlacesACommitAtItsCommitterDate (forsgren#254, step 4):
// a commit of a known lineage is placed at its committer date, when it landed,
// not at its author date: a mean of 15 hours, not 19; none is by author date,
// so the cell has no note.
func TestMainlineIntervalPlacesACommitAtItsCommitterDate(t *testing.T) {
	got := mainlineOf(mergedDeployment()...)
	if want := (placing{3, 2, 15 * time.Hour, 0}); placingOf(got) != want {
		t.Errorf("want a mean of 15 h by committer date and no commit by author date, got %+v", got)
	}
	if strings.Contains(got.Cell(), "author date") {
		t.Errorf("want no note in the cell, got %q", got.Cell())
	}
}

// TestMainlineIntervalKeepsTheOldApproximationForCommitsWithoutLineage
// (forsgren#254, step 4, decision #293): the commits of a deployment stored
// before the commits format v3 have no parents, so the first-parent chain is
// not known: every one of them counts, placed at its author date, and the cell
// says how many are: here all three, 5, 4 and 1 hours ago.
func TestMainlineIntervalKeepsTheOldApproximationForCommitsWithoutLineage(t *testing.T) {
	got := mainlineOf(lined(1, "a1", hoursAgo{5, -1}), lined(1, "a2", hoursAgo{4, -1}), lined(1, "a3", hoursAgo{1, -1}))
	if want := (placing{3, 2, 2 * time.Hour, 3}); placingOf(got) != want {
		t.Errorf("want the 3 commits by author date, a mean of 2 h, got %+v", got)
	}
	if want := "2 h ± 1 h 24 min (2) · median 2 h · p90 - · 3 commits timed by author date"; got.Cell() != want {
		t.Errorf("want cell %q, got %q", want, got.Cell())
	}
}

// TestMainlineIntervalMixesBothKindsOfDeployment (forsgren#254, step 4): a
// deployment stored before v3 next to one with its lineage: the merged
// deployment's three first-parent commits and the old one's only commit,
// authored 60 hours ago, are one sequence; one is by author date, named in the
// singular.
func TestMainlineIntervalMixesBothKindsOfDeployment(t *testing.T) {
	got := mainlineOf(append(mergedDeployment(), lined(2, "o1", hoursAgo{60, -1}))...)
	if want := (placing{4, 3, 50 * time.Hour / 3, 1}); placingOf(got) != want {
		t.Errorf("want 4 commits, 1 by author date, got %+v", got)
	}
	if want := " · 1 commit timed by author date"; !strings.HasSuffix(got.Cell(), want) {
		t.Errorf("want the cell to end with %q, got %q", want, got.Cell())
	}
}

// TestMainlineIntervalPlacesAChainCommitWithoutACommitterDateByAuthorDate
// (forsgren#254, step 4): a first-parent commit GitHub gave no committer date
// still counts, at its author date, never at the zero time, and is named:
// m1 at 50 hours ago, m2 and m3 at 20 and 10, a mean of 20 hours.
func TestMainlineIntervalPlacesAChainCommitWithoutACommitterDateByAuthorDate(t *testing.T) {
	commits := mergedDeployment()
	commits[0].CommittedAt = time.Time{}
	if want, got := (placing{3, 2, 20 * time.Hour, 1}), mainlineOf(commits...); placingOf(got) != want {
		t.Errorf("want m1 at its author date: 3 commits, a mean of 20 h, 1 by author date, got %+v", got)
	}
}

// TestMainlineIntervalTreatsALineageWithoutOneTipAsUnknown (forsgren#254,
// step 4): a comparison gives one tip, the commit no other names as a parent;
// a deployment with two has no first-parent chain to follow, so its commits
// keep the old approximation, every one by author date, and are named.
func TestMainlineIntervalTreatsALineageWithoutOneTipAsUnknown(t *testing.T) {
	got := mainlineOf(lined(1, "t1", hoursAgo{5, 3}, "base"), lined(1, "t2", hoursAgo{4, 2}, "base"))
	if want := (placing{2, 1, time.Hour, 2}); placingOf(got) != want {
		t.Errorf("want both commits by author date, a mean of 1 h, got %+v", got)
	}
}

// TestMainlineIntervalJudgesTheChainBeforeCountingACommitOnce (forsgren#254,
// step 4): b1, a branch commit of the merged deployment, is the tip of another
// deployment (another task), so it is on that one's chain and counts once:
// a branch copy seen first does not use up the commit.
func TestMainlineIntervalJudgesTheChainBeforeCountingACommitOnce(t *testing.T) {
	alone := lined(2, "b1", hoursAgo{48, 47}, "base")
	alone.Kind = history.KindWorkflow
	if got := mainlineOf(append(mergedDeployment(), alone)...); got.Commits != 4 {
		t.Errorf("want m1, m2, m3 and b1 once, 4 commits, got %+v", got)
	}
}

// TestMainlineIntervalNote (forsgren#254, step 4): none, one or several
// commits by author date.
func TestMainlineIntervalNote(t *testing.T) {
	for n, want := range map[int]string{0: "", 1: "1 commit timed by author date", 2: "2 commits timed by author date"} {
		if got := (MainlineInterval{ByAuthorDate: n}).Note(); got != want {
			t.Errorf("%d: want %q, got %q", n, want, got)
		}
	}
}
