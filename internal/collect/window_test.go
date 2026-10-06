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

// TestTheFirstRunReadsHistoryDaysBack (forsgren#57): with nothing stored for
// a repository, a deployment older than history_days before now is not
// read, and one inside it is.
func TestTheFirstRunReadsHistoryDaysBack(t *testing.T) {
	cases := []struct {
		name       string
		days       int
		created    string // deployment 1001, as GitHub says; 1002 is 2026-07-04
		wantStdout string
		wantRead   bool
	}{
		{"older than 90 days", 90, "2026-07-02T00:00:00Z", "acme/app: 1 new, 0 skipped (not final), 0 commits\n", false},
		{"300 days inside 365", 365, "2025-12-05T00:00:00Z", "acme/app: 2 new, 0 skipped (not final), 1 commits\n", true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			g := newGitHub(t)
			g.bodies[deploymentsPath] = list(
				deployment(1002, shaB, "deploy", "2026-07-04T00:00:00Z"),
				deployment(1001, shaA, "deploy", tc.created))
			g.bodies[statusesPath("1002")] = list(status(7, "success", "2026-07-04T00:05:00Z"))
			g.bodies[statusesPath("1001")] = list(status(6, "success", tc.created))
			g.bodies[comparePath(shaA, shaB)] = ahead(authored{shaB, time.Date(2026, 7, 3, 0, 0, 0, 0, time.UTC)})
			cfg := withHistoryDays(shop(production), tc.days)
			wantStdout(t, g.collect(t, cfg, historyPath(t), github.DefaultMaxPages), tc.wantStdout)
			if got := g.seen(statusesPath("1001")); (len(got) != 0) != tc.wantRead {
				t.Errorf("want the deployment read: %v, got %v", tc.wantRead, got)
			}
		})
	}
}

// TestALaterRunReadsFromAWeekBeforeTheNewestStored: once a repository has
// stored deployments, a run reads back to 7 days before the newest, so a
// deployment that was not final at the last run is still found. GitHub
// answers the one comparison, so stderr stays empty.
func TestALaterRunReadsFromAWeekBeforeTheNewestStored(t *testing.T) {
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list(
		deployment(1004, shaC, "deploy", "2026-09-25T00:00:00Z"),
		deployment(1003, shaB, "deploy", "2026-09-14T00:00:00Z"),
		deployment(1002, shaA, "deploy", "2026-09-12T00:00:00Z"))
	for _, id := range []string{"1004", "1003", "1002"} {
		g.bodies[statusesPath(id)] = list(status(7, "success", "2026-09-12T00:05:00Z"))
	}
	g.bodies[comparePath(shaB, shaC)] = ahead(authored{shaC, at(24, 0, 0)})
	path := stored(t, history.KindEnvironment, "production", at(20, 0, 0))
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	wantStdout(t, r, "acme/app: 2 new, 0 skipped (not final), 1 commits\n")
	wantNoStderr(t, r)
	if got := g.seen(statusesPath("1002")); len(got) != 0 {
		t.Errorf("want the deployment before the week not read, got %v", got)
	}
}

// TestALaterRunNeverReadsMoreThanHistoryDays (forsgren#57): a newest stored
// deployment long ago does not widen the window past history_days. The
// workflow's runs are asked from a day before the window, so no time zone
// loses one. GitHub answers the one comparison, so stderr stays empty.
func TestALaterRunNeverReadsMoreThanHistoryDays(t *testing.T) {
	cases := []struct {
		name      string
		days      int
		storedAt  time.Time
		runAt     string // run 5001, after the stored deployment
		wantSince string
		wantOut   string
	}{
		{"90 days", 90, time.Date(2026, 5, 1, 0, 0, 0, 0, time.UTC), "2026-06-01T00:00:00Z", "2026-07-02",
			"acme/app: 1 new, 0 skipped (not final), 1 commits\n"},
		{"365 days", 365, time.Date(2025, 8, 28, 0, 0, 0, 0, time.UTC), "2025-11-01T00:00:00Z", "2025-09-30",
			"acme/app: 2 new, 0 skipped (not final), 1 commits\n"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			g := newGitHub(t)
			g.bodies["/repos/acme/app"] = `{"default_branch": "trunk"}`
			g.bodies[runsPath] = runs(run(5002, shaB, "completed", "success", "2026-07-04T00:00:00Z"),
				run(5001, shaA, "completed", "success", tc.runAt))
			path := stored(t, history.KindWorkflow, "deploy.yml", tc.storedAt)
			g.bodies[comparePath(shaA, shaB)] = ahead(authored{shaB, time.Date(2026, 7, 3, 0, 0, 0, 0, time.UTC)})
			deploy := repository("acme/app", config.Workflow, "deploy.yml")
			r := g.collect(t, withHistoryDays(shop(deploy), tc.days), path, github.DefaultMaxPages)
			wantStdout(t, r, tc.wantOut)
			wantNoStderr(t, r)
			want := "created=%3E%3D" + tc.wantSince
			if got := g.seen(runsPath + "?"); len(got) != 1 || !strings.Contains(got[0], want) {
				t.Errorf("want the runs created from %s asked, got %v", tc.wantSince, got)
			}
		})
	}
}

// wantNoStderr fails unless the run printed nothing on stderr.
func wantNoStderr(t *testing.T, r result) {
	t.Helper()
	if r.stderr != "" {
		t.Errorf("want nothing on stderr, got %q", r.stderr)
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
	wantStdout(t, r, "acme/app: 1 new, 0 skipped (not final), 0 commits\n")
	want := "collect: acme/app: read the newest 1 page(s) only; older deployments were not read\n"
	if r.stderr != want {
		t.Errorf("want stderr %q, got %q", want, r.stderr)
	}
}

// withHistoryDays is cfg with history_days set (forsgren#57).
func withHistoryDays(cfg config.Config, days int) config.Config {
	cfg.HistoryDays = days
	return cfg
}
