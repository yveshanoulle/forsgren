package collect

import (
	"errors"
	"io/fs"
	"maps"
	"net/http"
	"os"
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// threeRepositories gives acme/web, acme/app and acme/docs one successful
// deployment each (IDs 1001, 2001, 3001) and returns the config that collects
// them in that order.
func threeRepositories(g *gitHub) config.Config {
	var repos []config.Repository
	for i, name := range []string{"acme/web", "acme/app", "acme/docs"} {
		id := int64(i+1)*1000 + 1
		base := "/repos/" + name + "/deployments"
		g.bodies[base] = list(deployment(id, shaA, "deploy", "2026-09-20T10:00:00Z"))
		g.bodies[base+"/"+strconv.FormatInt(id, 10)+"/statuses"] = list(status(id, "success", "2026-09-20T10:05:00Z"))
		repos = append(repos, repository(name, config.Environment, "production"))
	}
	return shop(repos...)
}

// TestARunStopsAtTheMarginAndKeepsWhatIsDone (forsgren#64, decision #238: a
// run cut short exits 0): acme/web is read in full; GitHub's answer to the
// list of acme/app's deployments says 80 of 5000 requests are left, below the
// margin of 250, so acme/app starts no further request (not its statuses),
// stores nothing and moves no read mark, and acme/docs, behind it, sends none
// at all. stderr names both with the reset time; the run exits 0.
func TestARunStopsAtTheMarginAndKeepsWhatIsDone(t *testing.T) {
	g := newGitHub(t)
	cfg := threeRepositories(g)
	g.left["/repos/acme/app/deployments"] = 80
	path := historyPath(t)
	r := g.collect(t, cfg, path, github.DefaultMaxPages)
	wantStdout(t, r, "acme/web: 1 new, 0 skipped (not final), 0 commits\n")
	wantCutShortOnStderr(t, r.stderr, g.resetAt, "acme/app", "acme/docs")
	if got := g.seen("/repos/acme/app/deployments/"); len(got) != 0 {
		t.Errorf("want no request after the margin for acme/app, got %v", got)
	}
	if got := g.seen("/repos/acme/docs"); len(got) != 0 {
		t.Errorf("want no request for acme/docs, got %v", got)
	}
	wantOnlyStored(t, path, "acme/web")
}

// wantCutShortOnStderr fails unless stderr names each repository as cut short
// with the time the budget resets.
func wantCutShortOnStderr(t *testing.T, stderr string, reset time.Time, repos ...string) {
	t.Helper()
	for _, repo := range repos {
		if !strings.Contains(stderr, "collect: cut short: "+repo+": ") {
			t.Errorf("want %s named as cut short on stderr, got %q", repo, stderr)
		}
	}
	if at := reset.UTC().Format(time.RFC3339); strings.Count(stderr, "resets at "+at) != len(repos) {
		t.Errorf("want the reset time %s on each line, got %q", at, stderr)
	}
}

// wantOnlyStored fails unless the history and reach.csv hold repo alone, and
// there is no withdrawn file: a repository cut short moves no read mark, and
// the one-time catch-up does not finish without it.
func wantOnlyStored(t *testing.T, path, repo string) {
	t.Helper()
	records, err := history.Load(path)
	if err != nil {
		t.Fatal(err)
	}
	var stored []string
	for _, r := range records {
		stored = append(stored, r.Repository)
	}
	if !slices.Equal(stored, []string{repo}) {
		t.Errorf("want only %s stored, got %v", repo, stored)
	}
	wantOnlyReach(t, path, repo)
	wantNoWithdrawnFile(t, path)
}

// wantOnlyReach fails unless reach.csv holds a row of repo alone.
func wantOnlyReach(t *testing.T, path, repo string) {
	t.Helper()
	reach, err := history.LoadReach(reachFileOf(path))
	if err != nil {
		t.Fatal(err)
	}
	if rows := slices.Sorted(maps.Keys(reach)); !slices.Equal(rows, []string{repo}) {
		t.Errorf("want only %s in reach.csv, got %v", repo, rows)
	}
}

// wantNoWithdrawnFile fails when the one-time catch-up wrote its file.
func wantNoWithdrawnFile(t *testing.T, path string) {
	t.Helper()
	if _, err := os.Stat(withdrawnFileBeside(path)); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("want no withdrawn file while a repository is cut short, got %v", err)
	}
}

// TestTheNextRunReadsWhatWasCutShort: with the budget back, the repositories
// that were cut short are read in full, and nothing is stored twice.
func TestTheNextRunReadsWhatWasCutShort(t *testing.T) {
	g := newGitHub(t)
	cfg := threeRepositories(g)
	g.left["/repos/acme/app/deployments"] = 80
	path := historyPath(t)
	g.collect(t, cfg, path, github.DefaultMaxPages)
	delete(g.left, "/repos/acme/app/deployments")
	r := g.collect(t, cfg, path, github.DefaultMaxPages)
	want := "acme/web: 0 new, 0 skipped (not final), 0 commits\n" +
		"acme/app: 1 new, 0 skipped (not final), 0 commits\n" +
		"acme/docs: 1 new, 0 skipped (not final), 0 commits\n"
	if r.err != nil || r.stdout != want {
		t.Errorf("want stdout %q and no error, got %q, %v (stderr %q)", want, r.stdout, r.err, r.stderr)
	}
}

// TestARequestRefusedAtZeroStaysAFailure: GitHub refusing a request with none
// left is a failed repository, as before; only a request not yet sent is cut
// short.
func TestARequestRefusedAtZeroStaysAFailure(t *testing.T) {
	g := newGitHub(t)
	cfg := threeRepositories(g)
	g.status["/repos/acme/web/deployments"] = http.StatusForbidden
	g.left["/repos/acme/web/deployments"] = 0
	r := g.collect(t, cfg, historyPath(t), github.DefaultMaxPages)
	if !errors.Is(r.err, ErrFailed) || !strings.Contains(r.stderr, "rate limit is reached") {
		t.Errorf("want a failed repository for the rate limit, got %v (stderr %q)", r.err, r.stderr)
	}
}

// TestASecondaryLimitFailsTheRepositoryAndIsNamedAsSuch (forsgren#64, step 3):
// GitHub's secondary rate limit, a Retry-After, is a failed repository like
// the primary one, but stderr names it as the secondary limit and says how
// long GitHub asks to wait, and it is not the budget's cut.
func TestASecondaryLimitFailsTheRepositoryAndIsNamedAsSuch(t *testing.T) {
	g := newGitHub(t)
	cfg := threeRepositories(g)
	g.status["/repos/acme/web/deployments"] = http.StatusTooManyRequests
	g.limited["/repos/acme/web/deployments"] = true
	r := g.collect(t, cfg, historyPath(t), github.DefaultMaxPages)
	if !errors.Is(r.err, ErrFailed) {
		t.Errorf("want a failed repository, got %v", r.err)
	}
	for _, want := range []string{"secondary rate limit is reached", "retry after 60 seconds"} {
		if !strings.Contains(r.stderr, want) {
			t.Errorf("want %q on stderr, got %q", want, r.stderr)
		}
	}
	if strings.Contains(r.stderr, "cut short") {
		t.Errorf("want a failure, not the budget's cut, got %q", r.stderr)
	}
}
