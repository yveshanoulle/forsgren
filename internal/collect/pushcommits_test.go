package collect

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/github"
)

// The commits each push brought to main (forsgren#397, step 3).

// TestAPushWithNoCountGetsNoCommitLines (forsgren#397, step 3): a compare
// that failed, was cut or did not reach the tip, and a force push, leave the
// commits column empty and write no line in push_commits.csv.
func TestAPushWithNoCountGetsNoCommitLines(t *testing.T) {
	g := pushesOnly(t,
		activityOf("force_push", "2026-09-22T10:00:00Z", shaC, shaD),
		activityOf("push", pushTime2, shaB, shaC),
		activityOf("push", pushTime1, shaA, shaB))
	g.bodies[comparePath(shaA, shaB)] = comparisonOf("ahead", 5,
		lineage{authoredBy{authored{shaB, at(20, 8, 0)}, ""}, []string{shaA}, ""})
	path := historyPath(t)
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatalf("want no error, got %v (stderr %q)", r.err, r.stderr)
	}
	dataOf(path).want(t, PushCommitsFile, pushCommitsHeader)
}

// TestThePushCommitsAreWrittenBeforeThePushes: a push_commits.csv that
// cannot be written fails the repository and stores no push, so a push is
// never stored without its commits; the next run reads it again.
func TestThePushCommitsAreWrittenBeforeThePushes(t *testing.T) {
	g := pushesOnly(t, activityOf("push", pushTime1, shaA, shaB))
	g.bodies[comparePath(shaA, shaB)] = chain(shaA, shaB)
	path := historyPath(t)
	data := dataOf(path)
	data.write(t, PushCommitsFile, pushCommitsHeader)
	if err := os.Chmod(filepath.Join(filepath.Dir(path), PushCommitsFile), 0o400); err != nil {
		t.Fatal(err)
	}
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if !errors.Is(r.err, ErrFailed) || !strings.Contains(r.stderr, PushCommitsFile) {
		t.Errorf("want ErrFailed and stderr naming %s, got %v, %q", PushCommitsFile, r.err, r.stderr)
	}
	data.want(t, PushesFile, "")
	data.want(t, PushesReadFile, "")
}

// TestAStoredPushIsNotReadAgainForItsCommits: a push stored before this
// version has no commit lines and gets none: it is not compared again.
func TestAStoredPushIsNotReadAgainForItsCommits(t *testing.T) {
	g := pushesOnly(t, activityOf("push", pushTime1, shaA, shaB))
	g.bodies[comparePath(shaA, shaB)] = chain(shaA, shaB)
	path := historyPath(t)
	dataOf(path).write(t, PushesFile, pushesHeader+linePush(pushTime1, shaA, shaB, "push", "false", "1"))
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatalf("want no error, got %v", r.err)
	}
	dataOf(path).want(t, PushCommitsFile, pushCommitsHeader)
	if got := g.seen("/repos/acme/app/compare/"); len(got) != 0 {
		t.Errorf("want no compare, got %v", got)
	}
}

// TestAPushWhoseCountCannotBeToldStoresNoBranchCommitsEither (forsgren#463,
// step 4, decision #468): a cut compare and a compare that does not reach the
// push's tip store no line, the branch commits included; a branch commit is
// never stored without its chain. (TestAPushWithNoCountGetsNoCommitLines
// already pins the force push and a cut compare of one commit.)
func TestAPushWhoseCountCannotBeToldStoresNoBranchCommitsEither(t *testing.T) {
	g := pushesOnly(t,
		activityOf("push", pushTime2, shaB, shaC),
		activityOf("push", pushTime1, shaA, shaB))
	// Cut: three commits listed of five, a branch commit among them.
	g.bodies[comparePath(shaA, shaB)] = comparisonOf("ahead", 5,
		lineage{authoredBy{authored{shaE, at(20, 7, 0)}, ""}, []string{shaA}, ""},
		lineage{authoredBy{authored{shaD, at(20, 8, 0)}, ""}, []string{shaA}, ""},
		lineage{authoredBy{authored{shaB, at(20, 9, 0)}, ""}, []string{shaA, shaE}, ""})
	// Whole but not reaching the tip shaC: a branch commit only.
	g.bodies[comparePath(shaB, shaC)] = comparisonOf("ahead", 1,
		lineage{authoredBy{authored{shaE, at(21, 8, 0)}, ""}, []string{shaB}, ""})
	path := historyPath(t)
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatalf("want no error, got %v (stderr %q)", r.err, r.stderr)
	}
	dataOf(path).want(t, PushCommitsFile, pushCommitsHeader)
}
