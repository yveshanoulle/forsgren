package collect

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/history"
)

const (
	deploymentsPath = "/repos/acme/app/deployments"
	runsPath        = "/repos/acme/app/actions/workflows/deploy.yml/runs"
)

func statusesPath(id string) string { return deploymentsPath + "/" + id + "/statuses" }

var production = repository("acme/app", config.Environment, "production")

// TestEnvironmentStoresTheFinalOutcomeOfEachDeployment: success when a
// status was success; failure when the last final status was failure or
// error; the task, the sha and the deployment's created_at are stored.
func TestEnvironmentStoresTheFinalOutcomeOfEachDeployment(t *testing.T) {
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list(
		deployment(1003, shaC, "deploy", "2026-09-20T10:00:00Z"),
		deployment(1002, shaB, "deploy:migrations", "2026-09-10T08:30:00Z"),
		deployment(1001, shaA, "deploy", "2026-09-01T07:00:00Z"))
	g.bodies[statusesPath("1003")] = list(status(3, "success", "2026-09-20T10:05:00Z"),
		status(2, "in_progress", "2026-09-20T10:01:00Z"))
	g.bodies[statusesPath("1002")] = list(status(5, "failure", "2026-09-10T08:40:00Z"),
		status(4, "in_progress", "2026-09-10T08:31:00Z"))
	g.bodies[statusesPath("1001")] = list(status(6, "error", "2026-09-01T07:05:00Z"))
	path := historyPath(t)
	wantStdout(t, g.collect(t, shop(production), path, github.DefaultMaxPages),
		"acme/app: 3 new, 0 skipped (not final), 0 commits\n")
	env := history.KindEnvironment
	wantRecords(t, path,
		record(env, "production", 1001, shaA, at(1, 7, 0), history.StateFailure, "deploy"),
		record(env, "production", 1002, shaB, at(10, 8, 30), history.StateFailure, "deploy:migrations"),
		record(env, "production", 1003, shaC, at(20, 10, 0), history.StateSuccess, "deploy"))
	if got := g.seen(deploymentsPath + "?"); len(got) != 1 || !strings.Contains(got[0], "environment=production") {
		t.Errorf("want the deployments of production read once, got %v", got)
	}
}

// TestInactiveAfterSuccessIsStillASuccess: GitHub marks a successful
// deployment inactive once a newer one replaces it; the latest status is
// then inactive, and the deployment was still a success.
func TestInactiveAfterSuccessIsStillASuccess(t *testing.T) {
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list(deployment(1003, shaC, "deploy", "2026-09-20T10:00:00Z"))
	g.bodies[statusesPath("1003")] = list(status(3, "inactive", "2026-09-21T09:00:00Z"),
		status(2, "success", "2026-09-20T10:05:00Z"))
	path := historyPath(t)
	wantStdout(t, g.collect(t, shop(production), path, github.DefaultMaxPages),
		"acme/app: 1 new, 0 skipped (not final), 0 commits\n")
	wantRecords(t, path,
		record(history.KindEnvironment, "production", 1003, shaC, at(20, 10, 0), history.StateSuccess, "deploy"))
}

// TestADeploymentThatIsNotFinalIsSkipped: no status yet, only pending,
// queued or in_progress, or only inactive: nothing is stored, and the count
// says so; a later run stores it once it has finished.
func TestADeploymentThatIsNotFinalIsSkipped(t *testing.T) {
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list(
		deployment(1004, shaA, "deploy", "2026-09-24T10:00:00Z"),
		deployment(1003, shaA, "deploy", "2026-09-23T10:00:00Z"),
		deployment(1002, shaB, "deploy", "2026-09-22T10:00:00Z"),
		deployment(1001, shaC, "deploy", "2026-09-21T10:00:00Z"))
	g.bodies[statusesPath("1004")] = list()
	g.bodies[statusesPath("1003")] = list(status(4, "in_progress", "2026-09-23T10:02:00Z"),
		status(3, "queued", "2026-09-23T10:01:00Z"), status(2, "pending", "2026-09-23T10:00:00Z"))
	g.bodies[statusesPath("1002")] = list(status(5, "inactive", "2026-09-22T11:00:00Z"))
	g.bodies[statusesPath("1001")] = list(status(6, "success", "2026-09-21T10:05:00Z"))
	path := historyPath(t)
	wantStdout(t, g.collect(t, shop(production), path, github.DefaultMaxPages),
		"acme/app: 1 new, 3 skipped (not final), 0 commits\n")
	wantRecords(t, path,
		record(history.KindEnvironment, "production", 1001, shaC, at(21, 10, 0), history.StateSuccess, "deploy"))
}

// TestTheConfiguredEnvironmentIsRead: environment=<name> reads that
// environment and stores its name.
func TestTheConfiguredEnvironmentIsRead(t *testing.T) {
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list(deployment(1001, shaA, "deploy", "2026-09-21T10:00:00Z"))
	g.bodies[statusesPath("1001")] = list(status(6, "success", "2026-09-21T10:05:00Z"))
	path := historyPath(t)
	staging := repository("acme/app", config.Environment, "staging east")
	wantStdout(t, g.collect(t, shop(staging), path, github.DefaultMaxPages),
		"acme/app: 1 new, 0 skipped (not final), 0 commits\n")
	wantRecords(t, path,
		record(history.KindEnvironment, "staging east", 1001, shaA, at(21, 10, 0), history.StateSuccess, "deploy"))
	if got := g.seen(deploymentsPath + "?"); len(got) != 1 || !strings.Contains(got[0], "environment=staging+east") {
		t.Errorf("want the deployments of staging east read, got %v", got)
	}
}

// TestWorkflowStoresTheCompletedRunsOnTheDefaultBranch: success and failure
// as they are, any other conclusion as other, a run still going skipped,
// and a run from a fork not counted at all. The run's ID, head_sha and
// run_started_at are stored.
func TestWorkflowStoresTheCompletedRunsOnTheDefaultBranch(t *testing.T) {
	g := newGitHub(t)
	g.bodies["/repos/acme/app"] = `{"full_name": "acme/app", "default_branch": "trunk"}`
	fork := strings.Replace(run(5006, shaA, "completed", "success", "2026-09-26T12:00:00Z"),
		`"full_name": "acme/app"`, `"full_name": "stranger/app"`, 1)
	g.bodies[runsPath] = runs(fork,
		run(5005, shaA, "in_progress", "", "2026-09-25T12:00:00Z"),
		run(5004, shaA, "completed", "timed_out", "2026-09-24T12:00:00Z"),
		run(5003, shaB, "completed", "cancelled", "2026-09-23T12:00:00Z"),
		run(5002, shaB, "completed", "failure", "2026-09-22T12:00:00Z"),
		run(5001, shaC, "completed", "success", "2026-09-21T12:00:00Z"))
	path := historyPath(t)
	deploy := repository("acme/app", config.Workflow, "deploy.yml")
	wantStdout(t, g.collect(t, shop(deploy), path, github.DefaultMaxPages),
		"acme/app: 4 new, 1 skipped (not final), 0 commits\n")
	wf := history.KindWorkflow
	wantRecords(t, path,
		record(wf, "deploy.yml", 5001, shaC, at(21, 12, 0), history.StateSuccess, ""),
		record(wf, "deploy.yml", 5002, shaB, at(22, 12, 0), history.StateFailure, ""),
		record(wf, "deploy.yml", 5003, shaB, at(23, 12, 0), history.StateOther, ""),
		record(wf, "deploy.yml", 5004, shaA, at(24, 12, 0), history.StateOther, ""))
	if got := g.seen(runsPath + "?"); len(got) != 1 || !strings.Contains(got[0], "branch=trunk") {
		t.Errorf("want the runs on trunk read, got %v", got)
	}
}

// TestReleaseStoresThePublishedReleasesAtTheirTagsCommit: drafts and
// prereleases are not deployments; a release is a success, at its
// publication time, with the commit of its tag and the tag as its task.
func TestReleaseStoresThePublishedReleasesAtTheirTagsCommit(t *testing.T) {
	g := newGitHub(t)
	g.bodies["/repos/acme/app/releases"] = list(
		release(9003, "v1.3.0", true, false, ""),
		release(9002, "v1.2.0", false, false, "2026-09-18T09:30:00Z"),
		release(9001, "v1.2.0-rc.1", false, true, "2026-09-12T09:10:00Z"))
	g.bodies["/repos/acme/app/commits/tags/v1.2.0"] = shaB
	path := historyPath(t)
	tools := repository("acme/app", config.Release, "")
	wantStdout(t, g.collect(t, shop(tools), path, github.DefaultMaxPages),
		"acme/app: 1 new, 0 skipped (not final), 0 commits\n")
	wantRecords(t, path, record(history.KindRelease, "", 9002, shaB, at(18, 9, 30), history.StateSuccess, "v1.2.0"))
	if got := g.seen("/repos/acme/app/commits/"); len(got) != 1 {
		t.Errorf("want one tag looked up, got %v", got)
	}
}

// TestASecondRunAddsNothing: what is stored is skipped, by Append's key
// and, for what costs a request per deployment, before the request.
func TestASecondRunAddsNothing(t *testing.T) {
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list(deployment(1001, shaA, "deploy", "2026-09-21T10:00:00Z"))
	g.bodies[statusesPath("1001")] = list(status(6, "success", "2026-09-21T10:05:00Z"))
	g.bodies["/repos/acme/api"] = `{"default_branch": "main"}`
	g.bodies["/repos/acme/api/actions/workflows/deploy.yml/runs"] = runs(
		strings.ReplaceAll(run(5001, shaC, "completed", "success", "2026-09-21T12:00:00Z"), "acme/app", "acme/api"))
	cfg := shop(production, repository("acme/api", config.Workflow, "deploy.yml"))
	path := historyPath(t)
	g.collect(t, cfg, path, github.DefaultMaxPages)
	before, err := os.ReadFile(filepath.Clean(path))
	if err != nil {
		t.Fatal(err)
	}
	wantStdout(t, g.collect(t, cfg, path, github.DefaultMaxPages),
		"acme/app: 0 new, 0 skipped (not final), 0 commits\nacme/api: 0 new, 0 skipped (not final), 0 commits\n")
	if after, _ := os.ReadFile(filepath.Clean(path)); string(after) != string(before) {
		t.Errorf("want the history unchanged, got\n%s", after)
	}
	if got := g.seen(statusesPath("1001")); len(got) != 1 {
		t.Errorf("want the statuses of a stored deployment read once, got %d reads", len(got))
	}
}

// TestAFailingRepositoryDoesNotStopTheOthers: each repository is tried; the
// one that fails is named on stderr and stores nothing, the others store
// theirs, and the run fails.
func TestAFailingRepositoryDoesNotStopTheOthers(t *testing.T) {
	g := newGitHub(t)
	g.bodies["/repos/acme/api/deployments"] = list(deployment(1001, shaA, "deploy", "2026-09-21T10:00:00Z"))
	g.bodies["/repos/acme/api/deployments/1001/statuses"] = list(status(6, "success", "2026-09-21T10:05:00Z"))
	path := historyPath(t)
	cfg := shop(production, repository("acme/api", config.Environment, "production"))
	r := g.collect(t, cfg, path, github.DefaultMaxPages)
	if !errors.Is(r.err, ErrFailed) || !strings.Contains(r.err.Error(), "1 of 2") {
		t.Errorf("want ErrFailed for 1 of 2, got %v", r.err)
	}
	if r.stdout != "acme/api: 1 new, 0 skipped (not final), 0 commits\n" {
		t.Errorf("want only acme/api's line on stdout, got %q", r.stdout)
	}
	if !strings.Contains(r.stderr, "check FORSGREN_TOKEN's access to acme/app") {
		t.Errorf("want acme/app's error on stderr, got %q", r.stderr)
	}
	wantRepositories(t, path, "acme/api")
}

// wantRepositories fails unless the history at path holds one record of
// each of repos, in order.
func wantRepositories(t *testing.T, path string, repos ...string) {
	t.Helper()
	got, err := history.Load(path)
	if err != nil {
		t.Fatal(err)
	}
	names := make([]string, 0, len(got))
	for _, r := range got {
		names = append(names, r.Repository)
	}
	if !slices.Equal(names, repos) {
		t.Errorf("want records of %v, got %v", repos, names)
	}
}

// TestARepositoryThatFailsHalfWayStoresNothing: the deployments are read,
// the statuses of one fail, and none of that repository's records are
// written.
func TestARepositoryThatFailsHalfWayStoresNothing(t *testing.T) {
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list(
		deployment(1002, shaB, "deploy", "2026-09-22T10:00:00Z"),
		deployment(1001, shaA, "deploy", "2026-09-21T10:00:00Z"))
	g.bodies[statusesPath("1002")] = list(status(7, "success", "2026-09-22T10:05:00Z"))
	g.bodies[statusesPath("1001")] = `{"message": "Server Error"}`
	g.status[statusesPath("1001")] = 500
	path := historyPath(t)
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	wantNothingStored(t, r, path, "acme/app: GitHub answered with an error: 500 Internal Server Error for "+
		statusesPath("1001"))
}

// TestAMalformedHistoryIsRefusedBeforeGitHubIsAsked.
func TestAMalformedHistoryIsRefusedBeforeGitHubIsAsked(t *testing.T) {
	g := newGitHub(t)
	path := historyPath(t)
	if err := os.MkdirAll(strings.TrimSuffix(path, "/deployments.csv"), 0o750); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("hello\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if !errors.Is(r.err, history.ErrMalformed) {
		t.Errorf("want ErrMalformed, got %v", r.err)
	}
	if got := g.seen("/"); len(got) != 0 {
		t.Errorf("want no request, got %v", got)
	}
}

// TestEachFailingCallFailsItsRepository: whichever call of a rule fails,
// the repository is named on stderr and nothing of it is written.
func TestEachFailingCallFailsItsRepository(t *testing.T) {
	branch := map[string]string{"/repos/acme/app": `{"default_branch": "trunk"}`}
	releases := map[string]string{"/repos/acme/app/releases": list(release(9002, "v1.2.0", false, false,
		"2026-09-18T09:30:00Z"))}
	for name, c := range map[string]struct {
		kind   config.DeploymentKind
		bodies map[string]string
		path   string
	}{
		"default branch": {config.Workflow, nil, "/repos/acme/app;"},
		"runs":           {config.Workflow, branch, runsPath},
		"releases":       {config.Release, nil, "/repos/acme/app/releases"},
		"tag commit":     {config.Release, releases, "/repos/acme/app/commits/tags/v1.2.0"},
	} {
		t.Run(name, func(t *testing.T) {
			g := newGitHub(t)
			for path, body := range c.bodies {
				g.bodies[path] = body
			}
			path := historyPath(t)
			r := g.collect(t, shop(repository("acme/app", c.kind, "deploy.yml")), path, github.DefaultMaxPages)
			wantNothingStored(t, r, path, c.path)
		})
	}
}

// TestADeploymentGitHubDescribesBadlyIsRefused: a commit that is not a SHA
// cannot be stored, so the repository fails and nothing of it is written.
func TestADeploymentGitHubDescribesBadlyIsRefused(t *testing.T) {
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list(deployment(1001, "main", "deploy", "2026-09-21T10:00:00Z"))
	g.bodies[statusesPath("1001")] = list(status(6, "success", "2026-09-21T10:05:00Z"))
	path := historyPath(t)
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	wantNothingStored(t, r, path, `acme/app: `+path+`: invalid history record: record 1: commit "main"`)
}

// wantNothingStored fails unless the run failed, stderr holds want and
// neither the history nor the commits file was written.
func wantNothingStored(t *testing.T, r result, path, want string) {
	t.Helper()
	if !errors.Is(r.err, ErrFailed) || r.stdout != "" || !strings.Contains(r.stderr, want) {
		t.Errorf("want the run to fail with %q on stderr, got %v, stdout %q, stderr %q", want, r.err, r.stdout, r.stderr)
	}
	for _, p := range []string{path, commitsPath(path)} {
		if _, err := os.Stat(p); !errors.Is(err, fs.ErrNotExist) {
			t.Errorf("want no %s written, got %v", filepath.Base(p), err)
		}
	}
}

// TestNoProjectsDoesNothing: no request, no file, no output.
func TestNoProjectsDoesNothing(t *testing.T) {
	g := newGitHub(t)
	path := historyPath(t)
	r := g.collect(t, config.Config{Version: 1, Projects: []config.Project{}}, path, github.DefaultMaxPages)
	wantStdout(t, r, "")
	if _, err := os.Stat(path); !errors.Is(err, fs.ErrNotExist) || len(g.seen("/")) != 0 {
		t.Errorf("want no file and no request, got %v, %v", err, g.seen("/"))
	}
}
