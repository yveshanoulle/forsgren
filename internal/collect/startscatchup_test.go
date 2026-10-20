package collect

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/github"
)

// startsCheckedBeside is data/starts_checked.csv next to the history at path.
func startsCheckedBeside(path string) string {
	return filepath.Join(filepath.Dir(path), "starts_checked.csv")
}

// storedWithoutAStart is a fake whose first run stored failure issue 43 of
// acme/app (opened 2026-09-22, still open) with an empty failure_start: its
// body and its comments have no block, as with an installation from before
// forsgren#37. The issues list is empty from now on, so only the catch-up
// can reach the issue again.
func storedWithoutAStart(t *testing.T) (*gitHub, string) {
	t.Helper()
	g := issuesOnly(t, issueJSON(43, "2026-09-22T08:00:00Z", "", "null"))
	path := historyPath(t)
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatal(r.err)
	}
	wantFailures(t, path, failure(43, at(22, 8, 0), time.Time{}, time.Time{}))
	g.bodies[issuesPath] = list()
	// An installation from before this arrived has no starts_checked.csv.
	if err := os.Remove(startsCheckedBeside(path)); err != nil {
		t.Fatal(err)
	}
	return g, path
}

// TestTheCatchUpReadsTheCommentsOfAStoredFailureOnce (forsgren#245): a stored
// failure issue that can still count and has an empty failure_start has its
// comments read, and a block found there is stored as a new line; the run's
// marks file notes the catch-up done, so the next run reads nothing.
func TestTheCatchUpReadsTheCommentsOfAStoredFailureOnce(t *testing.T) {
	g, path := storedWithoutAStart(t)
	g.bodies[commentsPath43] = list(commentJSON(1, blockAt("20")))
	asked := len(g.seen(commentsPath43))
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil || r.stderr != "" {
		t.Fatalf("want a quiet run, got %v, %q", r.err, r.stderr)
	}
	if got := len(g.seen(commentsPath43)) - asked; got != 1 {
		t.Errorf("want the comments of issue 43 read once by the catch-up, got %d requests", got)
	}
	wantFailures(t, path, failure(43, at(22, 8, 0), time.Time{}, at(20, 7, 12)))
	if _, err := os.Stat(startsCheckedBeside(path)); err != nil {
		t.Errorf("want the catch-up marked done in starts_checked.csv, got %v", err)
	}
	asked = len(g.seen(commentsPath43))
	g.collect(t, shop(production), path, github.DefaultMaxPages)
	if got := len(g.seen(commentsPath43)) - asked; got != 0 {
		t.Errorf("want no second catch-up, got %d requests", got)
	}
}

// TestTheCatchUpLeavesAFailureThatCannotCountOrHasItsStart: a closed failure
// opened before the window, and one that already has a failure-start, are not
// read.
func TestTheCatchUpLeavesAFailureThatCannotCountOrHasItsStart(t *testing.T) {
	g := issuesOnly(t,
		issueJSON(43, "2026-06-01T08:00:00Z", "2026-06-02T08:00:00Z", "null"),
		issueJSON(44, "2026-09-22T08:00:00Z", "", recordBlock))
	path := historyPath(t)
	g.collect(t, shop(production), path, github.DefaultMaxPages)
	g.bodies[issuesPath] = list()
	g.bodies[commentsPath43] = list(commentJSON(1, blockAt("20")))
	g.bodies[issuesPath+"/44/comments"] = list(commentJSON(1, blockAt("21")))
	asked := len(g.seen(issuesPath + "/4"))
	g.collect(t, shop(production), path, github.DefaultMaxPages)
	if got := len(g.seen(issuesPath+"/4")) - asked; got != 0 {
		t.Errorf("want no comments read for either issue, got %d requests", got)
	}
}

// TestTheCatchUpIsNotMarkedWhenARepositoryFailed: a refused read of the
// comments fails the repository, the failure stays as it was, and the
// catch-up is not marked done, so the next run does it again.
func TestTheCatchUpIsNotMarkedWhenARepositoryFailed(t *testing.T) {
	g, path := storedWithoutAStart(t)
	g.bodies[commentsPath43] = `{"message": "Resource not accessible by personal access token"}`
	g.status[commentsPath43] = 403
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err == nil {
		t.Fatalf("want the repository failed, got %q", r.stderr)
	}
	wantFailures(t, path, failure(43, at(22, 8, 0), time.Time{}, time.Time{}))
	if _, err := os.Stat(startsCheckedBeside(path)); err == nil {
		t.Errorf("want no starts_checked.csv after a failed repository")
	}
	delete(g.status, commentsPath43)
	g.bodies[commentsPath43] = list(commentJSON(1, blockAt("20")))
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatal(r.err)
	}
	wantFailures(t, path, failure(43, at(22, 8, 0), time.Time{}, at(20, 7, 12)))
}
