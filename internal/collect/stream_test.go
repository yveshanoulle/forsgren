package collect

import (
	"testing"

	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// historyHolding stores records in a new history and returns its path.
func historyHolding(t *testing.T, records ...history.Record) string {
	t.Helper()
	path := historyPath(t)
	if _, err := history.Append(path, records); err != nil {
		t.Fatal(err)
	}
	return path
}

// wantNoComparison fails unless collect asked GitHub for no comparison.
func wantNoComparison(t *testing.T, g *gitHub) {
	t.Helper()
	if got := g.seen("/repos/acme/app/compare/"); len(got) != 0 {
		t.Errorf("want no comparison, got %v", got)
	}
}

// TestAnotherEnvironmentIsAnotherStream: a deployment is compared within
// its stream only, and the environment is part of it. Once the config moves
// a repository from staging east to production, the first production
// deployment has no previous, whatever staging stored.
func TestAnotherEnvironmentIsAnotherStream(t *testing.T) {
	path := historyHolding(t,
		record(history.KindEnvironment, "staging east", 1001, shaA, at(21, 10, 0), history.StateSuccess, "deploy"))
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list(deployment(1002, shaB, "deploy", "2026-09-22T10:00:00Z"))
	g.succeeded("1002")
	g.bodies[comparePath(shaA, shaB)] = ahead(authored{shaB, at(22, 9, 0)})
	wantStdout(t, g.collect(t, shop(production), path, github.DefaultMaxPages),
		"acme/app: 1 new, 0 skipped (not final), 0 commits\n")
	wantNoComparison(t, g)
}

// TestADeploymentThatFinishesAfterANewerOneWasStoredGetsNoCommits
// (forsgren#16, step 7): 1002 was still running at the last run, while the
// newer 1003 succeeded and was stored, compared with 1001. Compared with
// 1001 too, 1002's commits would also be in 1003's list and count twice, so
// 1002 is stored without commits, and stderr says why.
func TestADeploymentThatFinishesAfterANewerOneWasStoredGetsNoCommits(t *testing.T) {
	path := historyHolding(t,
		record(history.KindEnvironment, "production", 1001, shaA, at(20, 10, 0), history.StateSuccess, "deploy"),
		record(history.KindEnvironment, "production", 1003, shaC, at(24, 10, 0), history.StateSuccess, "deploy"))
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list(
		deployment(1003, shaC, "deploy", "2026-09-24T10:00:00Z"),
		deployment(1002, shaB, "deploy", "2026-09-22T10:00:00Z"),
		deployment(1001, shaA, "deploy", "2026-09-20T10:00:00Z"))
	g.succeeded("1002")
	g.bodies[comparePath(shaA, shaB)] = ahead(authored{shaB, at(21, 9, 0)})
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	wantStdout(t, r, "acme/app: 1 new, 0 skipped (not final), 0 commits\n")
	want := "collect: acme/app: deployment 1002 finished after the newer deployment 1003 was stored; " +
		"lead time skips it, so no commit counts twice\n"
	if r.stderr != want {
		t.Errorf("want stderr %q, got %q", want, r.stderr)
	}
	wantCommits(t, path)
	wantNoComparison(t, g)
}
