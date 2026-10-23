package collect

import (
	"errors"
	"net/http"
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/github"
)

// The decision follow-ups for the merged pull requests (forsgren#320, step
// 2): what an interrupted, a skipped or an unreadable pull request does.

// unreadableCommits is the words of the warning for a commit page that
// cannot be read, never used for a missing date (decision #313).
const unreadableCommits = "the answer for its commits is malformed or unreadable"

// TestAnUnreadableCommitPageWarnsNamingThePullRequest (decision #313): a
// commit page that is not a list of commits has the created time stand in,
// as a missing date does, and stderr names the repository and the pull
// request with its own words; the pull requests after it are read on.
func TestAnUnreadableCommitPageWarnsNamingThePullRequest(t *testing.T) {
	g := pullsOnly(t, pull14, pull12)
	g.bodies[pull14.commitsPath()] = `{"message": "not a list"}`
	path := historyPath(t)
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	wantStdout(t, r, "acme/app: 0 new, 0 skipped (not final), 0 commits, 2 merged pull requests\n")
	dataOf(path).want(t, "pulls.csv", pullsHeader+pull12.line("2026-09-21T10:00:00Z", false)+pull14.line("", false))
	if want := "acme/app: pull request 14: " + unreadableCommits; !strings.Contains(r.stderr, want) ||
		!strings.Contains(r.stderr, "created time stands in") {
		t.Errorf("want stderr to hold %q and the created time standing in, got %q", want, r.stderr)
	}
}

// TestASystemicFailureOfTheCommitsIsNeverAMissingDate (decision #313): a
// server error on a pull request's commits fails the repository as before,
// and the created time never stands in for it.
func TestASystemicFailureOfTheCommitsIsNeverAMissingDate(t *testing.T) {
	g := pullsOnly(t, pull12)
	g.bodies[pull12.commitsPath()] = `{"message": "Server Error"}`
	g.status[pull12.commitsPath()] = http.StatusInternalServerError
	path := historyPath(t)
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if !errors.Is(r.err, ErrFailed) || strings.Contains(r.stderr, "created time stands in") {
		t.Errorf("want the repository failed, no created time standing in, got %v, %q", r.err, r.stderr)
	}
	dataOf(path).want(t, "pulls.csv", pullsHeader)
	dataOf(path).want(t, "pulls_read.csv", "")
}

// TestAnOldMergeIsSkippedAndTheReadGoesOn (decision #310): a pull request
// merged before history_days back is not stored and costs no commits
// request, whenever it was updated, and it ends nothing: the pull requests
// listed after it, by updated time, are still read.
func TestAnOldMergeIsSkippedAndTheReadGoesOn(t *testing.T) {
	mergedLongAgo := pull{51, "2025-09-01T08:00:00Z", "2026-09-29T00:00:00Z", "2025-09-02T00:00:00Z"}
	g := pullsOnly(t, mergedLongAgo, pull12, oldPull)
	path := historyPath(t)
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatalf("want no error, got %v (stderr %q)", r.err, r.stderr)
	}
	dataOf(path).want(t, "pulls.csv", pullsHeader+pull12.line("2026-09-21T10:00:00Z", false))
	if got := g.seen(mergedLongAgo.commitsPath()); len(got) != 0 {
		t.Errorf("want no commits asked of the old merge, got %v", got)
	}
}

// TestAPullRequestTheBudgetInterruptedIsReadByTheNextRun (decisions #304,
// #308): the pull request the budget stopped at is not stored and the mark
// stays before it, so the next run, with requests to spare, reads it.
func TestAPullRequestTheBudgetInterruptedIsReadByTheNextRun(t *testing.T) {
	g := pullsOnly(t, pull14, pull12)
	g.left[pullsPath] = 300
	g.left[pull14.commitsPath()] = 251
	path := historyPath(t)
	data := dataOf(path)
	data.write(t, "pulls_read.csv", pullsReadHeader+"acme/app,2026-09-20T08:00:00Z\n")
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatalf("want no error, got %v (stderr %q)", r.err, r.stderr)
	}
	data.want(t, "pulls.csv", pullsHeader+pull14.line("2026-09-23T10:00:00Z", false))
	g.left = map[string]int{}
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatalf("want no error on the next run, got %v (stderr %q)", r.err, r.stderr)
	}
	data.want(t, "pulls.csv", pullsHeader+pull14.line("2026-09-23T10:00:00Z", false)+
		pull12.line("2026-09-21T10:00:00Z", false))
	data.want(t, "pulls_read.csv", readNow)
}
