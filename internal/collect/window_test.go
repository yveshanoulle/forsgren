package collect

import (
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// stored writes one stored deployment of acme/app, created at created, into
// a new history and returns its path.
func stored(t *testing.T, kind history.Kind, name string, created time.Time) string {
	t.Helper()
	path := historyPath(t)
	r := record(kind, name, 1, shaA, created, history.StateSuccess, "")
	if _, err := history.Append(path, []history.Record{r}); err != nil {
		t.Fatal(err)
	}
	return path
}

// TestTheFirstRunReadsNinetyDaysBack: with nothing stored for a repository,
// a deployment older than 90 days before now is not read.
func TestTheFirstRunReadsNinetyDaysBack(t *testing.T) {
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list(
		deployment(1002, shaB, "deploy", "2026-07-04T00:00:00Z"),
		deployment(1001, shaA, "deploy", "2026-07-02T00:00:00Z"))
	g.bodies[statusesPath("1002")] = list(status(7, "success", "2026-07-04T00:05:00Z"))
	g.bodies[statusesPath("1001")] = list(status(6, "success", "2026-07-02T00:05:00Z"))
	path := historyPath(t)
	wantStdout(t, g.collect(t, shop(production), path, github.DefaultMaxPages), "acme/app: 1 new, 0 skipped (not final)\n")
	if got := g.seen(statusesPath("1001")); len(got) != 0 {
		t.Errorf("want the deployment older than 90 days not read, got %v", got)
	}
}

// TestALaterRunReadsFromAWeekBeforeTheNewestStored: once a repository has
// stored deployments, a run reads back to 7 days before the newest, so a
// deployment that was not final at the last run is still found.
func TestALaterRunReadsFromAWeekBeforeTheNewestStored(t *testing.T) {
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list(
		deployment(1004, shaC, "deploy", "2026-09-25T00:00:00Z"),
		deployment(1003, shaB, "deploy", "2026-09-14T00:00:00Z"),
		deployment(1002, shaA, "deploy", "2026-09-12T00:00:00Z"))
	for _, id := range []string{"1004", "1003", "1002"} {
		g.bodies[statusesPath(id)] = list(status(7, "success", "2026-09-12T00:05:00Z"))
	}
	path := stored(t, history.KindEnvironment, "production", at(20, 0, 0))
	wantStdout(t, g.collect(t, shop(production), path, github.DefaultMaxPages), "acme/app: 2 new, 0 skipped (not final)\n")
	if got := g.seen(statusesPath("1002")); len(got) != 0 {
		t.Errorf("want the deployment before the week not read, got %v", got)
	}
}

// TestALaterRunNeverReadsMoreThanNinetyDays: a newest stored deployment long
// ago does not widen the window past 90 days. The workflow's runs are asked
// from a day before the window, so no time zone loses one.
func TestALaterRunNeverReadsMoreThanNinetyDays(t *testing.T) {
	g := newGitHub(t)
	g.bodies["/repos/acme/app"] = `{"default_branch": "trunk"}`
	g.bodies[runsPath] = runs(run(5002, shaB, "completed", "success", "2026-07-04T00:00:00Z"),
		run(5001, shaA, "completed", "success", "2026-06-01T00:00:00Z"))
	path := stored(t, history.KindWorkflow, "deploy.yml", time.Date(2026, 5, 1, 0, 0, 0, 0, time.UTC))
	deploy := repository("acme/app", config.Workflow, "deploy.yml")
	wantStdout(t, g.collect(t, shop(deploy), path, github.DefaultMaxPages), "acme/app: 1 new, 0 skipped (not final)\n")
	if got := g.seen(runsPath + "?"); len(got) != 1 || !strings.Contains(got[0], "created=%3E%3D2026-07-02") {
		t.Errorf("want the runs created from 2026-07-02 asked, got %v", got)
	}
}

// TestAListCutAtThePageLimitIsReported: the newest pages are stored and
// stderr says that older ones were not read.
func TestAListCutAtThePageLimitIsReported(t *testing.T) {
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list(deployment(1001, shaA, "deploy", "2026-09-21T10:00:00Z"))
	g.bodies[statusesPath("1001")] = list(status(6, "success", "2026-09-21T10:05:00Z"))
	g.paged[deploymentsPath] = true
	r := g.collect(t, shop(production), historyPath(t), 1)
	wantStdout(t, r, "acme/app: 1 new, 0 skipped (not final)\n")
	want := "collect: acme/app: read the newest 1 page(s) only; older deployments were not read\n"
	if r.stderr != want {
		t.Errorf("want stderr %q, got %q", want, r.stderr)
	}
}
