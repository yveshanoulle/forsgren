package collect

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/history"
)

const (
	shaD = "dddddddddddddddddddddddddddddddddddddddd"
	shaE = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
	shaF = "ffffffffffffffffffffffffffffffffffffffff"
)

// comparePath is GitHub's comparison of base and head in acme/app.
func comparePath(base, head string) string { return "/repos/acme/app/compare/" + base + "..." + head }

// authored is one commit of a comparison: its SHA and its author date.
type authored struct {
	sha  string
	date time.Time
}

// comparison is GitHub's answer to a comparison with status and
// total_commits, listing commits oldest first.
func comparison(status string, total int, commits ...authored) string {
	items := make([]string, 0, len(commits))
	for _, c := range commits {
		items = append(items, fmt.Sprintf(`{"sha": %q, "commit": {"author": {"name": "Acme Dev", `+
			`"date": %q}, "committer": {"date": "2026-09-30T00:00:00Z"}, "message": "More"}}`,
			c.sha, c.date.Format(time.RFC3339)))
	}
	return fmt.Sprintf(`{"status": %q, "ahead_by": %d, "behind_by": 0, "total_commits": %d, "commits": %s, `+
		`"files": []}`, status, total, total, list(items...))
}

// ahead is a comparison GitHub gives whole: the head is ahead of the base
// by exactly these commits.
func ahead(commits ...authored) string { return comparison("ahead", len(commits), commits...) }

// commitsPath is where collect keeps the commits: next to the history.
func commitsPath(deployments string) string {
	return filepath.Join(filepath.Dir(deployments), "commits.csv")
}

// commit is a commit of acme/app's environment deployment id, deployed at
// deployed.
func commit(id int64, sha string, authoredAt, deployed time.Time) history.Commit {
	return history.Commit{Repository: "acme/app", Kind: history.KindEnvironment, DeploymentID: id, SHA: sha,
		AuthoredAt: authoredAt, DeployedAt: deployed}
}

// wantCommits fails unless the commits file next to the history at path
// holds want, in order.
func wantCommits(t *testing.T, path string, want ...history.Commit) {
	t.Helper()
	got, err := history.LoadCommits(commitsPath(path))
	if err != nil {
		t.Fatalf("want a commits file, got %v", err)
	}
	if !slices.Equal(got, want) {
		t.Errorf("want the commits\n%v\ngot\n%v", want, got)
	}
}

// succeeded makes each deployment of acme/app's production a success.
func (g *gitHub) succeeded(ids ...string) {
	for _, id := range ids {
		g.bodies[statusesPath(id)] = list(status(1, "success", "2026-09-01T00:00:00Z"))
	}
}

// TestTheFirstDeploymentGetsNoCommits: with no earlier success of its
// repository and task, a deployment has no known start, so nothing is
// compared; the commits file is still created, with its header.
func TestTheFirstDeploymentGetsNoCommits(t *testing.T) {
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list(deployment(1001, shaA, "deploy", "2026-09-21T10:00:00Z"))
	g.succeeded("1001")
	path := historyPath(t)
	wantStdout(t, g.collect(t, shop(production), path, github.DefaultMaxPages),
		"acme/app: 1 new, 0 skipped (not final), 0 commits\n")
	wantCommits(t, path)
	if got := g.seen("/repos/acme/app/compare/"); len(got) != 0 {
		t.Errorf("want no comparison, got %v", got)
	}
}

// TestASecondDeploymentGetsTheCommitsSinceThePrevious: the previous success
// is in the history; the new one's commits are those after the previous
// one's commit up to its own, each with its author date and the new
// deployment's created_at.
func TestASecondDeploymentGetsTheCommitsSinceThePrevious(t *testing.T) {
	path := historyPath(t)
	held := record(history.KindEnvironment, "production", 1001, shaA, at(20, 10, 0), history.StateSuccess, "deploy")
	if _, err := history.Append(path, []history.Record{held}); err != nil {
		t.Fatal(err)
	}
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list(deployment(1002, shaB, "deploy", "2026-09-22T10:00:00Z"))
	g.succeeded("1002")
	g.bodies[comparePath(shaA, shaB)] = ahead(authored{shaC, at(21, 9, 0)}, authored{shaB, at(22, 8, 0)})
	wantStdout(t, g.collect(t, shop(production), path, github.DefaultMaxPages),
		"acme/app: 1 new, 0 skipped (not final), 2 commits\n")
	wantCommits(t, path, commit(1002, shaC, at(21, 9, 0), at(22, 10, 0)), commit(1002, shaB, at(22, 8, 0), at(22, 10, 0)))
}

// TestThePreviousCanBeStoredInTheSameRun: GitHub lists the newest first;
// the deployments of one run are taken oldest first, so the second one's
// previous is the first, read in the same run.
func TestThePreviousCanBeStoredInTheSameRun(t *testing.T) {
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list(
		deployment(1003, shaC, "deploy", "2026-09-24T10:00:00Z"),
		deployment(1002, shaB, "deploy", "2026-09-22T10:00:00Z"),
		deployment(1001, shaA, "deploy", "2026-09-20T10:00:00Z"))
	g.succeeded("1003", "1002", "1001")
	g.bodies[comparePath(shaA, shaB)] = ahead(authored{shaB, at(21, 9, 0)})
	g.bodies[comparePath(shaB, shaC)] = ahead(authored{shaD, at(23, 9, 0)}, authored{shaC, at(23, 10, 0)})
	path := historyPath(t)
	wantStdout(t, g.collect(t, shop(production), path, github.DefaultMaxPages),
		"acme/app: 3 new, 0 skipped (not final), 3 commits\n")
	wantCommits(t, path, commit(1002, shaB, at(21, 9, 0), at(22, 10, 0)),
		commit(1003, shaD, at(23, 9, 0), at(24, 10, 0)), commit(1003, shaC, at(23, 10, 0), at(24, 10, 0)))
}

// TestThePreviousHasTheSameTask: one repository deploying two tasks to one
// environment measures each against its own previous deployment.
func TestThePreviousHasTheSameTask(t *testing.T) {
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list(
		deployment(1004, shaD, "deploy-admin", "2026-09-23T10:00:00Z"),
		deployment(1003, shaC, "deploy-api", "2026-09-22T10:00:00Z"),
		deployment(1002, shaB, "deploy-admin", "2026-09-21T10:00:00Z"),
		deployment(1001, shaA, "deploy-api", "2026-09-20T10:00:00Z"))
	g.succeeded("1004", "1003", "1002", "1001")
	g.bodies[comparePath(shaA, shaC)] = ahead(authored{shaC, at(21, 12, 0)})
	g.bodies[comparePath(shaB, shaD)] = ahead(authored{shaE, at(22, 12, 0)}, authored{shaD, at(23, 9, 0)})
	path := historyPath(t)
	wantStdout(t, g.collect(t, shop(production), path, github.DefaultMaxPages),
		"acme/app: 4 new, 0 skipped (not final), 3 commits\n")
	wantCommits(t, path, commit(1003, shaC, at(21, 12, 0), at(22, 10, 0)),
		commit(1004, shaE, at(22, 12, 0), at(23, 10, 0)), commit(1004, shaD, at(23, 9, 0), at(23, 10, 0)))
	if got := g.seen("/repos/acme/app/compare/"); len(got) != 2 {
		t.Errorf("want two comparisons, one per task, got %v", got)
	}
}

// TestAFailedDeploymentsCommitsRollToTheNextSuccess: a failure is never a
// previous and gets no commits; the next success is compared with the
// success before the failure, so the failed deployment's commits are its.
func TestAFailedDeploymentsCommitsRollToTheNextSuccess(t *testing.T) {
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list(
		deployment(1003, shaC, "deploy", "2026-09-22T10:00:00Z"),
		deployment(1002, shaB, "deploy", "2026-09-21T10:00:00Z"),
		deployment(1001, shaA, "deploy", "2026-09-20T10:00:00Z"))
	g.succeeded("1003", "1001")
	g.bodies[statusesPath("1002")] = list(status(2, "failure", "2026-09-21T10:05:00Z"))
	g.bodies[comparePath(shaA, shaC)] = ahead(authored{shaB, at(20, 12, 0)}, authored{shaC, at(21, 12, 0)})
	path := historyPath(t)
	wantStdout(t, g.collect(t, shop(production), path, github.DefaultMaxPages),
		"acme/app: 3 new, 0 skipped (not final), 2 commits\n")
	wantCommits(t, path, commit(1003, shaB, at(20, 12, 0), at(22, 10, 0)),
		commit(1003, shaC, at(21, 12, 0), at(22, 10, 0)))
	if got := g.seen("/repos/acme/app/compare/"); len(got) != 1 {
		t.Errorf("want only the two successes compared, got %v", got)
	}
}

// TestAWorkflowRunThatIsNotASuccessIsSkippedToo: a cancelled run is stored
// as other, is never a previous, and its commits roll on like a failure's.
func TestAWorkflowRunThatIsNotASuccessIsSkippedToo(t *testing.T) {
	g := newGitHub(t)
	g.bodies["/repos/acme/app"] = `{"default_branch": "trunk"}`
	g.bodies[runsPath] = runs(
		run(5003, shaC, "completed", "success", "2026-09-22T12:00:00Z"),
		run(5002, shaB, "completed", "cancelled", "2026-09-21T12:00:00Z"),
		run(5001, shaA, "completed", "success", "2026-09-20T12:00:00Z"))
	g.bodies[comparePath(shaA, shaC)] = ahead(authored{shaC, at(21, 9, 0)})
	path := historyPath(t)
	deploy := repository("acme/app", config.Workflow, "deploy.yml")
	wantStdout(t, g.collect(t, shop(deploy), path, github.DefaultMaxPages),
		"acme/app: 3 new, 0 skipped (not final), 1 commits\n")
	wantCommits(t, path, history.Commit{Repository: "acme/app", Kind: history.KindWorkflow, DeploymentID: 5003,
		SHA: shaC, AuthoredAt: at(21, 9, 0), DeployedAt: at(22, 12, 0)})
}

// TestAReleaseFollowsThePreviousReleaseWhateverItsTag: a release's task is
// its tag, a new one each time, so releases are one line of deployments:
// each is compared with the release before it.
func TestAReleaseFollowsThePreviousReleaseWhateverItsTag(t *testing.T) {
	g := newGitHub(t)
	g.bodies["/repos/acme/app/releases"] = list(
		release(9002, "v1.1.0", false, false, "2026-09-18T09:30:00Z"),
		release(9001, "v1.0.0", false, false, "2026-09-10T09:30:00Z"))
	g.bodies["/repos/acme/app/commits/tags/v1.1.0"] = shaB
	g.bodies["/repos/acme/app/commits/tags/v1.0.0"] = shaA
	g.bodies[comparePath(shaA, shaB)] = ahead(authored{shaB, at(17, 9, 0)})
	path := historyPath(t)
	wantStdout(t, g.collect(t, shop(repository("acme/app", config.Release, "")), path, github.DefaultMaxPages),
		"acme/app: 2 new, 0 skipped (not final), 1 commits\n")
	wantCommits(t, path, history.Commit{Repository: "acme/app", Kind: history.KindRelease, DeploymentID: 9002,
		SHA: shaB, AuthoredAt: at(17, 9, 0), DeployedAt: at(18, 9, 30)})
}

// twoDeployments is a run with a first success and a second one to compare.
func twoDeployments(t *testing.T) *gitHub {
	t.Helper()
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list(
		deployment(1002, shaB, "deploy", "2026-09-22T10:00:00Z"),
		deployment(1001, shaA, "deploy", "2026-09-20T10:00:00Z"))
	g.succeeded("1002", "1001")
	return g
}

// TestACutComparisonStoresNoCommits: GitHub gives fewer commits than its
// total, so the oldest are kept and the newest lost; a skewed sample is
// worse than none, so that deployment gets no commits and stderr says so.
// The deployment is stored, the run does not fail, and a second run does
// not compare it again.
func TestACutComparisonStoresNoCommits(t *testing.T) {
	g := twoDeployments(t)
	g.bodies[comparePath(shaA, shaB)] = comparison("ahead", 300, authored{shaC, at(21, 9, 0)},
		authored{shaD, at(21, 10, 0)})
	path := historyPath(t)
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	wantStdout(t, r, "acme/app: 2 new, 0 skipped (not final), 0 commits\n")
	want := "collect: acme/app: deployment 1002: 2 commits compared, list cut; lead time skips this deployment\n"
	if r.stderr != want {
		t.Errorf("want stderr %q, got %q", want, r.stderr)
	}
	wantCommits(t, path)
	wantRepositories(t, path, "acme/app", "acme/app")
	wantStdout(t, g.collect(t, shop(production), path, github.DefaultMaxPages),
		"acme/app: 0 new, 0 skipped (not final), 0 commits\n")
	if got := g.seen("/repos/acme/app/compare/"); len(got) != 1 {
		t.Errorf("want the cut deployment compared once, got %v", got)
	}
}

// TestAHistoryOfAnotherShapeStoresNoCommits: a base that is not an
// ancestor of the head (a force-push, or a rollback to an older commit) or
// a commit GitHub does not have is about the history's shape, not access:
// that deployment gets no commits, stderr names both SHAs, the deployments
// are stored and the run does not fail.
func TestAHistoryOfAnotherShapeStoresNoCommits(t *testing.T) {
	for name, c := range map[string]struct {
		body string // empty: GitHub answers 404
		want string
	}{
		"not an ancestor":  {comparison("diverged", 0), "the base is not an ancestor of the head"},
		"a missing commit": {"", "a commit of the comparison is missing"},
	} {
		t.Run(name, func(t *testing.T) {
			g := twoDeployments(t)
			if c.body != "" {
				g.bodies[comparePath(shaA, shaB)] = c.body
			}
			path := historyPath(t)
			r := g.collect(t, shop(production), path, github.DefaultMaxPages)
			wantStdout(t, r, "acme/app: 2 new, 0 skipped (not final), 0 commits\n")
			wantStderr(t, r, "collect: acme/app: "+c.want, shaA, shaB, "; lead time skips deployment 1002\n")
			wantCommits(t, path)
			wantRepositories(t, path, "acme/app", "acme/app")
		})
	}
}

// wantStderr fails unless stderr holds each of want.
func wantStderr(t *testing.T, r result, want ...string) {
	t.Helper()
	for _, w := range want {
		if !strings.Contains(r.stderr, w) {
			t.Errorf("want %q on stderr, got %q", w, r.stderr)
		}
	}
}

// TestARefusedComparisonFailsTheRepository: no access, a rate limit or any
// other error of a comparison fails the repository like any other call:
// neither its deployments nor its commits are written.
func TestARefusedComparisonFailsTheRepository(t *testing.T) {
	g := twoDeployments(t)
	g.bodies[comparePath(shaA, shaB)] = `{"message": "Bad credentials"}`
	g.status[comparePath(shaA, shaB)] = 401
	path := historyPath(t)
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	wantNothingStored(t, r, path, "check FORSGREN_TOKEN's access to acme/app")
}

// TestACommitsFileThatCannotBeWrittenLosesNoCommits (forsgren#16, step 7):
// when commits.csv cannot be written, the repository fails and its
// deployments are not stored either, so the next run reads them again and
// stores them with their commits; a deployment is never stored without the
// commits it was compared for.
func TestACommitsFileThatCannotBeWrittenLosesNoCommits(t *testing.T) {
	g := twoDeployments(t)
	g.bodies[comparePath(shaA, shaB)] = ahead(authored{shaB, at(21, 9, 0)})
	path := historyPath(t)
	if _, err := history.AppendCommits(commitsPath(path), nil); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(commitsPath(path), 0o400); err != nil {
		t.Fatal(err)
	}
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); !errors.Is(r.err, ErrFailed) {
		t.Fatalf("want the run to fail on a read-only commits file, got %v (stderr %q)", r.err, r.stderr)
	}
	if err := os.Chmod(commitsPath(path), 0o600); err != nil {
		t.Fatal(err)
	}
	wantStdout(t, g.collect(t, shop(production), path, github.DefaultMaxPages),
		"acme/app: 2 new, 0 skipped (not final), 1 commits\n")
	wantCommits(t, path, commit(1002, shaB, at(21, 9, 0), at(22, 10, 0)))
}

// TestASecondRunComparesNothingAgain: a deployment's commits are compared
// when the deployment is stored, once; the next run neither asks GitHub
// again nor writes the commits file.
func TestASecondRunComparesNothingAgain(t *testing.T) {
	g := twoDeployments(t)
	g.bodies[comparePath(shaA, shaB)] = ahead(authored{shaB, at(21, 9, 0)})
	path := historyPath(t)
	wantStdout(t, g.collect(t, shop(production), path, github.DefaultMaxPages),
		"acme/app: 2 new, 0 skipped (not final), 1 commits\n")
	before, err := os.ReadFile(filepath.Clean(commitsPath(path)))
	if err != nil {
		t.Fatal(err)
	}
	wantStdout(t, g.collect(t, shop(production), path, github.DefaultMaxPages),
		"acme/app: 0 new, 0 skipped (not final), 0 commits\n")
	if after, _ := os.ReadFile(filepath.Clean(commitsPath(path))); string(after) != string(before) {
		t.Errorf("want the commits file unchanged, got\n%s", after)
	}
	if got := g.seen("/repos/acme/app/compare/"); len(got) != 1 {
		t.Errorf("want one comparison over both runs, got %v", got)
	}
}

// TestAMalformedCommitsFileIsRefusedBeforeGitHubIsAsked: like the history,
// a commits file that cannot be read stops the run before any request.
func TestAMalformedCommitsFileIsRefusedBeforeGitHubIsAsked(t *testing.T) {
	g := newGitHub(t)
	path := historyPath(t)
	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(commitsPath(path), []byte("# forsgren commits v9\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if !errors.Is(r.err, history.ErrUnknownVersion) {
		t.Errorf("want ErrUnknownVersion, got %v", r.err)
	}
	if got := g.seen("/"); len(got) != 0 {
		t.Errorf("want no request, got %v", got)
	}
}

// TestTheCountIsPerRepository: each repository's line counts the commits
// stored for it.
func TestTheCountIsPerRepository(t *testing.T) {
	g := twoDeployments(t)
	g.bodies[comparePath(shaA, shaB)] = ahead(authored{shaE, at(21, 9, 0)}, authored{shaB, at(21, 10, 0)})
	g.bodies["/repos/acme/api/deployments"] = list(deployment(2001, shaF, "deploy", "2026-09-21T10:00:00Z"))
	g.bodies["/repos/acme/api/deployments/2001/statuses"] = list(status(6, "success", "2026-09-21T10:05:00Z"))
	cfg := shop(production, repository("acme/api", config.Environment, "production"))
	wantStdout(t, g.collect(t, cfg, historyPath(t), github.DefaultMaxPages),
		"acme/app: 2 new, 0 skipped (not final), 2 commits\nacme/api: 1 new, 0 skipped (not final), 0 commits\n")
}
