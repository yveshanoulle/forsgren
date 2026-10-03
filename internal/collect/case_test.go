package collect

import (
	"testing"

	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// TestARepositoryStoredInAnotherCaseIsTheSameRepository: GitHub's
// repository names ignore case, and so does the config; a history line of
// Acme/App is acme/app's (forsgren#12, step 8). Its deployment is neither
// asked about again nor stored twice, and the window starts a week before
// it, not 90 days back.
func TestARepositoryStoredInAnotherCaseIsTheSameRepository(t *testing.T) {
	path := historyPath(t)
	held := record(history.KindEnvironment, "production", 1001, shaA, at(21, 10, 0), history.StateSuccess, "deploy")
	held.Repository = "Acme/App"
	if _, err := history.Append(path, []history.Record{held}); err != nil {
		t.Fatal(err)
	}
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list(
		deployment(1002, shaB, "deploy", "2026-09-22T10:00:00Z"),
		deployment(1001, shaA, "deploy", "2026-09-21T10:00:00Z"),
		deployment(1000, shaC, "deploy", "2026-09-01T10:00:00Z"))
	g.bodies[statusesPath("1002")] = list(status(7, "success", "2026-09-22T10:05:00Z"))
	g.bodies[statusesPath("1001")] = list(status(6, "success", "2026-09-21T10:05:00Z"))
	g.bodies[statusesPath("1000")] = list(status(5, "success", "2026-09-01T10:05:00Z"))
	wantStdout(t, g.collect(t, shop(production), path, github.DefaultMaxPages), "acme/app: 1 new, 0 skipped (not final)\n")
	if got := g.seen(statusesPath("1001")); len(got) != 0 {
		t.Errorf("want the statuses of the deployment held as Acme/App not read, got %v", got)
	}
	if got := g.seen(statusesPath("1000")); len(got) != 0 {
		t.Errorf("want nothing read from more than a week before the deployment held as Acme/App, got %v", got)
	}
	wantRecords(t, path, held,
		record(history.KindEnvironment, "production", 1002, shaB, at(22, 10, 0), history.StateSuccess, "deploy"))
}
