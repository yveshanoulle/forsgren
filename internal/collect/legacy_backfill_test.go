package collect

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// legacyCommitsHeader is the v3 file an installation has after the v3 upgrade
// rewrote its older file: the lines it already held keep their author,
// parents and committer date empty.
const legacyCommitsHeader = "# forsgren commits v3\n" +
	"repository,kind,deployment_id,commit,authored_at,deployed_at,author,parents,committed_at\n"

// threeSuccesses are acme/app's production deployments 1001 to 1003, all
// successes of the task deploy.
func threeSuccesses() []history.Record {
	return []history.Record{
		record(history.KindEnvironment, "production", 1001, shaA, at(20, 10, 0), history.StateSuccess, "deploy"),
		record(history.KindEnvironment, "production", 1002, shaB, at(22, 10, 0), history.StateSuccess, "deploy"),
		record(history.KindEnvironment, "production", 1003, shaD, at(23, 10, 0), history.StateSuccess, "deploy"),
	}
}

// withLegacyCommits stores three successes of acme/app (1001 to 1003) and a
// commits file in which deployment 1002 holds two legacy lines (the commits
// C and B, nothing but their dates) and deployment 1003 holds one line that
// already has its author, parents and committer date. The fake answers the
// comparison of 1001 to 1002 with the author login, parents and committer
// date of both commits, the commit B linked to no account (forsgren#385).
// It answers no other comparison, so any other one fails the run.
func withLegacyCommits(t *testing.T) (*gitHub, string) {
	t.Helper()
	path := historyPath(t)
	if _, err := history.Append(path, threeSuccesses()); err != nil {
		t.Fatal(err)
	}
	stored := legacyCommitsHeader +
		"acme/app,environment,1002," + shaC + ",2026-09-21T09:00:00Z,2026-09-22T10:00:00Z,,,\n" +
		"acme/app,environment,1002," + shaB + ",2026-09-22T08:00:00Z,2026-09-22T10:00:00Z,,,\n" +
		"acme/app,environment,1003," + shaD + ",2026-09-23T08:00:00Z,2026-09-23T10:00:00Z,bob-dev," + shaB +
		",2026-09-23T08:30:00Z\n"
	if err := os.WriteFile(commitsPath(path), []byte(stored), 0o600); err != nil {
		t.Fatal(err)
	}
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list(deployment(1003, shaD, "deploy", "2026-09-23T10:00:00Z"),
		deployment(1002, shaB, "deploy", "2026-09-22T10:00:00Z"),
		deployment(1001, shaA, "deploy", "2026-09-20T10:00:00Z"))
	g.succeeded("1003", "1002", "1001")
	g.bodies[comparePath(shaA, shaB)] = comparisonOf("ahead", 2,
		lineage{authoredBy{authored{shaC, at(21, 9, 0)}, "ada-dev"}, []string{shaA}, "2026-09-21T09:30:00Z"},
		lineage{authoredBy{authored{shaB, at(22, 8, 0)}, ""}, []string{shaC}, "2026-09-22T08:30:00Z"})
	return g, path
}

// backfilledBeside is data/commits_backfilled.csv next to the history at
// path, the mark file that notes the repositories whose legacy commits were
// backfilled (forsgren#385).
func backfilledBeside(path string) string {
	return filepath.Join(filepath.Dir(path), "commits_backfilled.csv")
}

// collectLegacy runs collect over withLegacyCommits and fails on an error.
func collectLegacy(t *testing.T) (*gitHub, string) {
	t.Helper()
	g, path := withLegacyCommits(t)
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatal(r.err)
	}
	return g, path
}

// TestCollectBackfillsTheLegacyCommits (forsgren#385, step 1): the lines of
// data/commits.csv stored before the commits format v3 (no author, no
// parents, no committer date) have all three filled from one comparison of
// their deployment with its previous success. A commit GitHub links to no
// account keeps an empty login but gets its parents and committer date. A
// line that is not legacy stays as it is, and its deployment is not compared.
func TestCollectBackfillsTheLegacyCommits(t *testing.T) {
	g, path := collectLegacy(t)
	filled := commit(1002, shaC, at(21, 9, 0), at(22, 10, 0))
	filled.Author = "ada-dev"
	noAccount := commit(1002, shaB, at(22, 8, 0), at(22, 10, 0))
	untouched := commit(1003, shaD, at(23, 8, 0), at(23, 10, 0))
	untouched.Author = "bob-dev"
	wantCommits(t, path, landed(filled, at(21, 9, 30), shaA), landed(noAccount, at(22, 8, 30), shaC),
		landed(untouched, at(23, 8, 30), shaB))
	if got := g.seen("/repos/acme/app/compare/"); len(got) != 1 || !strings.HasPrefix(got[0], comparePath(shaA, shaB)) {
		t.Errorf("want one comparison, of deployment 1002 with its previous success, got %v", got)
	}
}

// TestTheBackfillLeavesTheDeploymentsAlone (forsgren#385, step 1): the
// deployments file is the same bytes after the backfill.
func TestTheBackfillLeavesTheDeploymentsAlone(t *testing.T) {
	g, path := withLegacyCommits(t)
	before, err := os.ReadFile(filepath.Clean(path))
	if err != nil {
		t.Fatal(err)
	}
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatal(r.err)
	}
	wantRecords(t, path, threeSuccesses()...)
	if after, _ := os.ReadFile(filepath.Clean(path)); string(after) != string(before) {
		t.Errorf("want the deployments file unchanged, got\n%s", after)
	}
	if got := g.seen("/repos/acme/app/compare/"); len(got) != 1 {
		t.Errorf("want the backfill to have compared once, got %v", got)
	}
}

// TestTheBackfillNotesTheRepositoryAndComparesNothingAgain (forsgren#385,
// step 1): a mark file notes acme/app as backfilled, and a second run makes
// no comparison for it.
func TestTheBackfillNotesTheRepositoryAndComparesNothingAgain(t *testing.T) {
	g, path := collectLegacy(t)
	wantBackfillMark(t, path)
	asked := len(g.seen("/repos/acme/app/compare/"))
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatal(r.err)
	}
	if asked == 0 {
		t.Errorf("want the first run to have compared, so the second run's silence means something")
	}
	if got := len(g.seen("/repos/acme/app/compare/")) - asked; got != 0 {
		t.Errorf("want no comparison on the second run, got %d", got)
	}
}
