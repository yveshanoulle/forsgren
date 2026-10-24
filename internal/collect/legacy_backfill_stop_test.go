package collect

import (
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"reflect"
	"strconv"
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/github"
)

// legacyLine is the file line of a legacy commit of acme/app's production
// deployment id: no author, no parents, no committer date.
func legacyLine(id int, sha, authored, deployed string) string {
	return "acme/app,environment," + strconv.Itoa(id) + "," + sha + "," + authored + "," + deployed + ",,,\n"
}

// withLegacyDeployments is withLegacyCommits with legacy lines in the
// deployments 1002 (the commit B, C) and 1003 (the commit D) and none in 1001;
// the fake knows 1003's author, parents and committer date as well.
func withLegacyDeployments(t *testing.T) (*gitHub, string) {
	t.Helper()
	g, path := withLegacyCommits(t)
	stored := legacyCommitsHeader +
		legacyLine(1002, shaC, "2026-09-21T09:00:00Z", "2026-09-22T10:00:00Z") +
		legacyLine(1002, shaB, "2026-09-22T08:00:00Z", "2026-09-22T10:00:00Z") +
		legacyLine(1003, shaD, "2026-09-23T08:00:00Z", "2026-09-23T10:00:00Z")
	storeCommitsFile(t, path, stored)
	g.bodies[comparePath(shaB, shaD)] = comparisonOf("ahead", 1,
		lineage{authoredBy{authored{shaD, at(23, 8, 0)}, "bob-dev"}, []string{shaB}, "2026-09-23T08:30:00Z"})
	return g, path
}

// wantNoBackfillMark fails when the mark file notes acme/app.
func wantNoBackfillMark(t *testing.T, path string) {
	t.Helper()
	mark, err := os.ReadFile(filepath.Clean(backfilledBeside(path)))
	if err == nil && strings.Contains(string(mark), "acme/app") {
		t.Errorf("want acme/app not marked as backfilled, got\n%s", mark)
	}
}

// wantBackfillMark fails unless the mark file notes acme/app.
func wantBackfillMark(t *testing.T, path string) {
	t.Helper()
	mark, err := os.ReadFile(filepath.Clean(backfilledBeside(path)))
	if err != nil || !strings.Contains(string(mark), "acme/app,") {
		t.Errorf("want acme/app noted as backfilled in commits_backfilled.csv, got %q, %v", mark, err)
	}
}

// storeCommitsFile replaces the commits file next to the history at path.
func storeCommitsFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(commitsPath(path), []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
}

// comparisonsAsked is how many comparisons the fake has been asked.
func (g *gitHub) comparisonsAsked() int { return len(g.seen("/repos/acme/app/compare/")) }

// wantOnly1003Filled fails unless the commits file holds the commit D
// of deployment 1003 filled and the lines of 1002 still legacy.
func wantOnly1003Filled(t *testing.T, path string) {
	t.Helper()
	filled := commit(1003, shaD, at(23, 8, 0), at(23, 10, 0))
	filled.Author = "bob-dev"
	wantCommits(t, path, commit(1002, shaC, at(21, 9, 0), at(22, 10, 0)),
		commit(1002, shaB, at(22, 8, 0), at(22, 10, 0)), landed(filled, at(23, 8, 30), shaB))
}

// TestTheBackfillCutShortAtTheBudgetKeepsWhatItFilledAndIsNotMarked
// (forsgren#385, step 2): the newest deployment is compared first; when the
// answer leaves the budget no room for another comparison, the repository is
// cut short, not failed, what was filled is written whole, the older legacy
// lines stay as they are, and no mark is written, so the next run continues.
func TestTheBackfillCutShortAtTheBudgetKeepsWhatItFilledAndIsNotMarked(t *testing.T) {
	g, path := withLegacyDeployments(t)
	g.left[comparePath(shaB, shaD)] = 80
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if r.err != nil || !strings.Contains(r.stderr, "collect: cut short: acme/app: ") {
		t.Fatalf("want acme/app cut short and no error, got %v, %q", r.err, r.stderr)
	}
	wantOnly1003Filled(t, path)
	wantNoBackfillMark(t, path)
	if got := g.seen("/repos/acme/app/compare/"); len(got) != 1 {
		t.Errorf("want the one comparison the budget allowed, got %v", got)
	}
	want := Report{BackfillCut: []string{"acme/app"}, Reset: g.resetAt.UTC()}
	if !reflect.DeepEqual(g.report, want) {
		t.Errorf("want the report %+v, got %+v", want, g.report)
	}
}

// TestTheBackfillIsNotMarkedWhileAnotherRepositoryFailed (forsgren#385, step
// 3): acme/app is backfilled whole, but acme/web failed in the same run, so no
// mark is written and the backfill is tried again; the next run, with acme/web
// well, notes both. The lines already filled are not compared again.
func TestTheBackfillIsNotMarkedWhileAnotherRepositoryFailed(t *testing.T) {
	g, path := withLegacyCommits(t)
	web := repository("acme/web", config.Environment, "production")
	g.bodies["/repos/acme/web/deployments"] = `{"message": "Server Error"}`
	g.status["/repos/acme/web/deployments"] = http.StatusInternalServerError
	if r := g.collect(t, shop(production, web), path, github.DefaultMaxPages); !errors.Is(r.err, ErrFailed) {
		t.Fatalf("want acme/web failed, got %v", r.err)
	}
	wantNoBackfillMark(t, path)
	if g.comparisonsAsked() != 1 {
		t.Fatalf("want acme/app compared once, got %d", g.comparisonsAsked())
	}
	delete(g.status, "/repos/acme/web/deployments")
	g.bodies["/repos/acme/web/deployments"] = list()
	if r := g.collect(t, shop(production, web), path, github.DefaultMaxPages); r.err != nil {
		t.Fatal(r.err)
	}
	wantBackfillMark(t, path)
	if g.comparisonsAsked() != 1 {
		t.Errorf("want the filled lines not compared again, got %d comparisons", g.comparisonsAsked())
	}
}

// TestARefusedBackfillComparisonFailsTheRepositoryAndIsNotMarked
// (forsgren#385, step 2): any other error of a comparison fails the
// repository like a new deployment's, after the newer deployment's lines were
// filled and written; no mark is written.
func TestARefusedBackfillComparisonFailsTheRepositoryAndIsNotMarked(t *testing.T) {
	g, path := withLegacyDeployments(t)
	g.bodies[comparePath(shaA, shaB)] = `{"message": "Bad credentials"}`
	g.status[comparePath(shaA, shaB)] = 401
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err == nil {
		t.Fatalf("want the repository failed, got %q", r.stderr)
	}
	wantOnly1003Filled(t, path)
	wantNoBackfillMark(t, path)
}

// TestALineGitHubNoLongerListsStaysLegacyAndTheBackfillIsStillMarked
// (forsgren#385, step 2): a previous that is not an ancestor leaves the
// deployment's lines legacy with a warning; a deployment with no previous
// success is not compared; neither keeps the repository from being marked,
// and a second run compares nothing.
func TestALineGitHubNoLongerListsStaysLegacyAndTheBackfillIsStillMarked(t *testing.T) {
	g, path := withLegacyDeployments(t)
	g.bodies[comparePath(shaA, shaB)] = comparison("diverged", 0)
	stored := legacyCommitsHeader + legacyLine(1001, shaA, "2026-09-19T09:00:00Z", "2026-09-20T10:00:00Z") +
		legacyLine(1002, shaB, "2026-09-22T08:00:00Z", "2026-09-22T10:00:00Z")
	storeCommitsFile(t, path, stored)
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if r.err != nil {
		t.Fatalf("want no error, got %v", r.err)
	}
	wantStderr(t, r, "collect: backfill: deployment 1002: acme/app: ", shaA, shaB,
		"; its legacy commits stay without author\n")
	if strings.Contains(r.stderr, "lead time") {
		t.Errorf("want the backfill's own wording, not the lead time's, got %q", r.stderr)
	}
	wantCommits(t, path, commit(1001, shaA, at(19, 9, 0), at(20, 10, 0)),
		commit(1002, shaB, at(22, 8, 0), at(22, 10, 0)))
	wantBackfillMark(t, path)
	g.collect(t, shop(production), path, github.DefaultMaxPages)
	if got := g.comparisonsAsked(); got != 1 {
		t.Errorf("want one comparison over both runs, got %d", got)
	}
}

// TestAFileWithNoLegacyLinesIsNotRewrittenButTheRepositoryIsMarked
// (forsgren#385, step 2): with every line current, nothing is compared, the
// commits file keeps its modification time, and the repository is marked.
func TestAFileWithNoLegacyLinesIsNotRewrittenButTheRepositoryIsMarked(t *testing.T) {
	g, path := withLegacyCommits(t)
	current := legacyCommitsHeader + "acme/app,environment,1003," + shaD +
		",2026-09-23T08:00:00Z,2026-09-23T10:00:00Z,bob-dev," + shaB + ",2026-09-23T08:30:00Z\n"
	storeCommitsFile(t, path, current)
	before, _ := os.Stat(commitsPath(path))
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatal(r.err)
	}
	after, _ := os.Stat(commitsPath(path))
	if !after.ModTime().Equal(before.ModTime()) || g.comparisonsAsked() != 0 {
		t.Errorf("want the file untouched and nothing compared, got %v, %d comparisons", after.ModTime(),
			g.comparisonsAsked())
	}
	wantBackfillMark(t, path)
}
