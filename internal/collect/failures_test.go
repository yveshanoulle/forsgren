package collect

import (
	"errors"
	"fmt"
	"io/fs"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/history"
)

const issuesPath = "/repos/acme/app/issues"

// recordBlock is the body of a failure issue with its record block, users
// first hit at 09:12 in Brussels on 2026-09-20 (07:12 UTC).
const recordBlock = `"Checkout crashes.\r\n\r\nfailure-start: 2026-09-20T09:12+02:00\r\nfailed-build: 12.345\r\n"`

// issueJSON is a failure issue of acme/app as GitHub lists it: number,
// created at created, closed at closed (null when empty), with body (JSON,
// null for none).
func issueJSON(number int, created, closed, body string) string {
	c := "null"
	if closed != "" {
		c = fmt.Sprintf("%q", closed)
	}
	return fmt.Sprintf(`{"id": %d, "number": %d, "title": "Checkout crashes", "state": "open", `+
		`"labels": [{"name": "failure"}], "created_at": %q, "updated_at": %q, "closed_at": %s, "body": %s}`,
		7000+number, number, created, created, c, body)
}

// failure is a stored failure issue of acme/app.
func failure(number int64, opened, closed, start time.Time) history.Failure {
	return history.Failure{Repository: "acme/app", Issue: number, OpenedAt: opened, ClosedAt: closed, FailureStart: start}
}

// issuesOnly is a fake GitHub where acme/app has no deployment to
// production, and the failure issues items.
func issuesOnly(t *testing.T, items ...string) *gitHub {
	t.Helper()
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list()
	g.bodies[issuesPath] = list(items...)
	return g
}

// wantFailures fails unless the failures file next to the history at path
// holds want, each issue as its newest line says.
func wantFailures(t *testing.T, path string, want ...history.Failure) {
	t.Helper()
	got, err := history.LoadFailures(filepath.Join(filepath.Dir(path), "failures.csv"))
	if err != nil {
		t.Fatalf("want a failures file, got %v", err)
	}
	if !slices.Equal(got, want) {
		t.Errorf("want the failures\n%v\ngot\n%v", want, got)
	}
}

// TestCollectStoresTheFailureIssuesOfEachRepository (forsgren#18, step 3):
// the issues labelled failure, open or closed, updated in the last 90 days,
// go to data/failures.csv next to the history, with their record block's
// failure-start; stdout counts them after the commits.
func TestCollectStoresTheFailureIssuesOfEachRepository(t *testing.T) {
	g := issuesOnly(t, issueJSON(42, "2026-09-20T08:00:00Z", "2026-09-21T09:30:00Z", recordBlock),
		issueJSON(41, "2026-09-15T07:45:00Z", "", recordBlock))
	path := historyPath(t)
	wantStdout(t, g.collect(t, withFirstRunDays(shop(production), 90), path, github.DefaultMaxPages),
		"acme/app: 0 new, 0 skipped (not final), 0 commits, 2 failure issues\n")
	start := at(20, 7, 12)
	wantFailures(t, path, failure(41, at(15, 7, 45), time.Time{}, start), failure(42, at(20, 8, 0), at(21, 9, 30), start))
	asked := g.seen(issuesPath + "?")
	if len(asked) != 1 {
		t.Fatalf("want the failure issues asked once, got %v", asked)
	}
	for _, want := range []string{"labels=failure", "state=all", "since=2026-07-03T00%3A00%3A00Z"} {
		if !strings.Contains(asked[0], want) {
			t.Errorf("want %s in the query, got %v", want, asked[0])
		}
	}
}

// TestAClosedIssueIsStoredAgainAndAnUnchangedOneIsNot: the next run finds
// issue 41 closed, which is a new line, and issue 42 as it was, which is
// not; a run with nothing new says nothing of failure issues.
func TestAClosedIssueIsStoredAgainAndAnUnchangedOneIsNot(t *testing.T) {
	closed42 := issueJSON(42, "2026-09-20T08:00:00Z", "2026-09-21T09:30:00Z", recordBlock)
	g := issuesOnly(t, closed42, issueJSON(41, "2026-09-15T07:45:00Z", "", recordBlock))
	path := historyPath(t)
	g.collect(t, shop(production), path, github.DefaultMaxPages)
	g.bodies[issuesPath] = list(closed42, issueJSON(41, "2026-09-15T07:45:00Z", "2026-09-30T10:00:00Z", recordBlock))
	for _, want := range []string{"acme/app: 0 new, 0 skipped (not final), 0 commits, 1 failure issues\n",
		"acme/app: 0 new, 0 skipped (not final), 0 commits\n"} {
		wantStdout(t, g.collect(t, shop(production), path, github.DefaultMaxPages), want)
	}
	start := at(20, 7, 12)
	wantFailures(t, path, failure(41, at(15, 7, 45), at(30, 10, 0), start),
		failure(42, at(20, 8, 0), at(21, 9, 30), start))
}

// TestAFailureIssueWithoutAFailureStartIsStoredAndNamed: the issue counts
// all the same, its failure_start empty, and stderr names it, once, when it
// is first stored.
func TestAFailureIssueWithoutAFailureStartIsStoredAndNamed(t *testing.T) {
	g := issuesOnly(t, issueJSON(43, "2026-09-22T08:00:00Z", "", "null"))
	path := historyPath(t)
	for _, wantErr := range []string{
		"collect: acme/app: failure issue #43 has no failure-start line forsgren can read in its body\n", "",
	} {
		r := g.collect(t, shop(production), path, github.DefaultMaxPages)
		if r.err != nil || r.stderr != wantErr {
			t.Errorf("want stderr %q, got %q, %v", wantErr, r.stderr, r.err)
		}
	}
	wantFailures(t, path, failure(43, at(22, 8, 0), time.Time{}, time.Time{}))
}

// TestAClosedIssueWithoutAFailureStartIsNotNamedAgain (forsgren#18, step
// 6, review): the issue was named when it was first stored; its closing is
// stored as a new line without naming it again.
func TestAClosedIssueWithoutAFailureStartIsNotNamedAgain(t *testing.T) {
	g := issuesOnly(t, issueJSON(43, "2026-09-22T08:00:00Z", "", "null"))
	path := historyPath(t)
	g.collect(t, shop(production), path, github.DefaultMaxPages)
	g.bodies[issuesPath] = list(issueJSON(43, "2026-09-22T08:00:00Z", "2026-09-23T08:00:00Z", "null"))
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	wantStdout(t, r, "acme/app: 0 new, 0 skipped (not final), 0 commits, 1 failure issues\n")
	wantNoStderr(t, r)
	wantFailures(t, path, failure(43, at(22, 8, 0), at(23, 8, 0), time.Time{}))
}

// TestARefusedIssueListFailsTheRepositoryWhole: when GitHub refuses the
// issues, the repository is stored not at all, its deployments neither.
func TestARefusedIssueListFailsTheRepositoryWhole(t *testing.T) {
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list(deployment(1001, shaA, "deploy", "2026-09-21T10:00:00Z"))
	g.bodies[statusesPath("1001")] = list(status(6, "success", "2026-09-21T10:05:00Z"))
	g.bodies[issuesPath] = `{"message": "Resource not accessible by personal access token"}`
	g.status[issuesPath] = http.StatusForbidden
	path := historyPath(t)
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if !errors.Is(r.err, ErrFailed) || !strings.Contains(r.stderr, "check FORSGREN_TOKEN's access to acme/app") {
		t.Errorf("want the repository failed for the token's access, got %v, %q", r.err, r.stderr)
	}
	if _, err := os.Stat(path); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("want no history written, got %v", err)
	}
}

// TestAFailuresFileItCannotReadIsRefusedFirst: a malformed failures file
// fails the run before GitHub is asked anything, and stays as it was.
func TestAFailuresFileItCannotReadIsRefusedFirst(t *testing.T) {
	g := newGitHub(t)
	path := historyPath(t)
	failures := filepath.Join(filepath.Dir(path), "failures.csv")
	if err := os.MkdirAll(filepath.Dir(failures), 0o750); err != nil {
		t.Fatal(err)
	}
	content := "# forsgren failures v9\n"
	if err := os.WriteFile(failures, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if !errors.Is(r.err, history.ErrUnknownVersion) || len(g.seen("/")) != 0 {
		t.Errorf("want ErrUnknownVersion before any request, got %v after %v", r.err, g.seen("/"))
	}
	if got, _ := os.ReadFile(filepath.Clean(failures)); string(got) != content {
		t.Errorf("want the failures file untouched, got %q", got)
	}
}

// TestACutIssueListIsReported: the newest pages are stored and stderr says
// older failure issues were not read.
func TestACutIssueListIsReported(t *testing.T) {
	g := issuesOnly(t, issueJSON(42, "2026-09-20T08:00:00Z", "", recordBlock))
	g.paged[issuesPath] = true
	r := g.collect(t, shop(production), historyPath(t), 1)
	wantStdout(t, r, "acme/app: 0 new, 0 skipped (not final), 0 commits, 1 failure issues\n")
	want := "collect: acme/app: read the newest 1 page(s) of failure issues only; older ones were not read\n"
	if r.stderr != want {
		t.Errorf("want stderr %q, got %q", want, r.stderr)
	}
}

// TestAFailuresFileThatCannotBeWrittenStoresNoDeployment: when
// failures.csv cannot be written, the repository fails and its deployments
// are not stored either, so the next run reads them, and the issues, again.
func TestAFailuresFileThatCannotBeWrittenStoresNoDeployment(t *testing.T) {
	g := issuesOnly(t, issueJSON(42, "2026-09-20T08:00:00Z", "", recordBlock))
	g.bodies[deploymentsPath] = list(deployment(1001, shaA, "deploy", "2026-09-21T10:00:00Z"))
	g.bodies[statusesPath("1001")] = list(status(6, "success", "2026-09-21T10:05:00Z"))
	path := historyPath(t)
	failures := filepath.Join(filepath.Dir(path), "failures.csv")
	if _, err := history.AppendFailures(failures, nil); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(failures, 0o400); err != nil {
		t.Fatal(err)
	}
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); !errors.Is(r.err, ErrFailed) {
		t.Fatalf("want the run to fail on a read-only failures file, got %v (stderr %q)", r.err, r.stderr)
	}
	if _, err := os.Stat(path); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("want no history written, got %v", err)
	}
	if err := os.Chmod(failures, 0o600); err != nil {
		t.Fatal(err)
	}
	wantStdout(t, g.collect(t, shop(production), path, github.DefaultMaxPages),
		"acme/app: 1 new, 0 skipped (not final), 0 commits, 1 failure issues\n")
}
