package collect

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// The commits of each merged pull request (forsgren#463, step 6).

const pullCommitsHeader = "# forsgren pull commits v1\nrepository,number,sha,author,authored_at\n"

// commitBy is one commit of a pull request as GitHub lists it: its SHA, its
// top-level author login (null when empty) and its author date.
func commitBy(sha, login, authored string) string {
	a := "null"
	if login != "" {
		a = fmt.Sprintf(`{"login": %q, "type": "User"}`, login)
	}
	return fmt.Sprintf(`{"sha": %q, "author": %s, "commit": {"author": {"name": "Someone", "date": %q}, `+
		`"committer": {"date": "2026-09-30T00:00:00Z"}}}`, sha, a, authored)
}

// linePullCommit is the pull_commits.csv line of the commit sha of pull
// request n of acme/app.
func linePullCommit(n int, sha, login, authored string) string {
	return fmt.Sprintf("acme/app,%d,%s,%s,%s\n", n, sha, login, authored)
}

// twoCommits is the commit list of pull request 12 with two commits, the
// later one listed first, the second by no account.
func twoCommits() string {
	return list(commitBy(shaD, "", "2026-09-21T10:00:00Z"), commitBy(shaE, "acme-dev", "2026-09-20T10:00:00Z"))
}

// TestAMergedPullRequestWritesItsCommits (forsgren#463, step 6): each commit
// of a merged pull request is a line of pull_commits.csv with its login (empty
// for no account) and author date, oldest first; the pull request's own line
// is what it was.
func TestAMergedPullRequestWritesItsCommits(t *testing.T) {
	g := pullsOnly(t, pull12)
	g.bodies[pull12.commitsPath()] = twoCommits()
	path := historyPath(t)
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatalf("want no error, got %v (stderr %q)", r.err, r.stderr)
	}
	data := dataOf(path)
	data.want(t, PullCommitsFile, pullCommitsHeader+
		linePullCommit(12, shaE, "acme-dev", "2026-09-20T10:00:00Z")+
		linePullCommit(12, shaD, "", "2026-09-21T10:00:00Z"))
	data.want(t, "pulls.csv", pullsHeader+pull12.line("2026-09-20T10:00:00Z", false))
}

// TestABotsPullRequestWritesItsCommitsToo (decision #467): every commit
// counts, whoever opened the pull request.
func TestABotsPullRequestWritesItsCommitsToo(t *testing.T) {
	g := pullsOnly(t, pull12)
	g.bodies[pullsPath] = list(pull12.jsonBy(`{"login": "robot[bot]", "type": "Bot"}`))
	g.bodies[pull12.commitsPath()] = list(commitBy(shaD, "robot[bot]", "2026-09-20T10:00:00Z"))
	path := historyPath(t)
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatalf("want no error, got %v (stderr %q)", r.err, r.stderr)
	}
	dataOf(path).want(t, PullCommitsFile, pullCommitsHeader+
		linePullCommit(12, shaD, "robot[bot]", "2026-09-20T10:00:00Z"))
}

// TestAPullRequestWhoseCreatedTimeStandsInWritesNoCommits: no commit, a
// commit without an author date and a commit list that cannot be read give
// no commit line (forsgren#300, decision #313).
func TestAPullRequestWhoseCreatedTimeStandsInWritesNoCommits(t *testing.T) {
	g := pullsOnly(t, pull14, pull15)
	g.bodies[pull14.commitsPath()] = list()
	g.bodies[pull15.commitsPath()] = `{"message": "not a list"}`
	path := historyPath(t)
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatalf("want no error, got %v (stderr %q)", r.err, r.stderr)
	}
	dataOf(path).want(t, PullCommitsFile, pullCommitsHeader)
	dataOf(path).want(t, "pulls.csv", pullsHeader+pull14.line("", false)+pull15.line("", false))
}

// TestACutCommitListStoresTheCommitsItRead: a list cut at the page limit
// writes the commits of the page read; the pulls line says it is cut.
func TestACutCommitListStoresTheCommitsItRead(t *testing.T) {
	g := pullsOnly(t, pull12)
	g.bodies[pull12.commitsPath()] = twoCommits()
	g.paged[pull12.commitsPath()] = true
	path := historyPath(t)
	if r := g.collect(t, shop(production), path, 1); r.err != nil {
		t.Fatalf("want no error, got %v (stderr %q)", r.err, r.stderr)
	}
	data := dataOf(path)
	data.want(t, PullCommitsFile, pullCommitsHeader+
		linePullCommit(12, shaE, "acme-dev", "2026-09-20T10:00:00Z")+
		linePullCommit(12, shaD, "", "2026-09-21T10:00:00Z"))
	data.want(t, "pulls.csv", pullsHeader+pull12.line("2026-09-20T10:00:00Z", true))
}

// TestThePullCommitsAreWrittenBeforeThePulls: a pulls.csv that cannot be
// written fails the repository after the commits are written, so a pull
// request is never stored without its commits; the next run reads it again.
func TestThePullCommitsAreWrittenBeforeThePulls(t *testing.T) {
	g := pullsOnly(t, pull12)
	g.bodies[pull12.commitsPath()] = twoCommits()
	path := historyPath(t)
	dataOf(path).write(t, "pulls.csv", pullsHeader)
	if err := os.Chmod(filepath.Join(filepath.Dir(path), "pulls.csv"), 0o400); err != nil {
		t.Fatal(err)
	}
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if !errors.Is(r.err, ErrFailed) || !strings.Contains(r.stderr, "pulls.csv") {
		t.Errorf("want ErrFailed and stderr naming pulls.csv, got %v, %q", r.err, r.stderr)
	}
	dataOf(path).want(t, PullCommitsFile, pullCommitsHeader+
		linePullCommit(12, shaE, "acme-dev", "2026-09-20T10:00:00Z")+
		linePullCommit(12, shaD, "", "2026-09-21T10:00:00Z"))
	dataOf(path).want(t, "pulls_read.csv", "")
}

// TestAPullCommitsFileThatCannotBeReadRefusesTheRun: a pull_commits.csv not
// in its format is an error naming it, before GitHub is asked anything.
func TestAPullCommitsFileThatCannotBeReadRefusesTheRun(t *testing.T) {
	g := pullsOnly(t, pull12)
	path := historyPath(t)
	dataOf(path).write(t, PullCommitsFile, "nope\n")
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if !errors.Is(r.err, history.ErrMalformed) || !strings.Contains(r.err.Error(), PullCommitsFile) {
		t.Errorf("want ErrMalformed naming %s, got %v", PullCommitsFile, r.err)
	}
	if got := g.seen("/"); len(got) != 0 {
		t.Errorf("want GitHub asked nothing, got %v", got)
	}
}

// TestAPullCommitsFileThatCannotBeWrittenFailsTheRepositoryAndStoresNoPull: the
// error names pull_commits.csv, no pull request is stored without its
// commits and no mark moves.
func TestAPullCommitsFileThatCannotBeWrittenFailsTheRepositoryAndStoresNoPull(t *testing.T) {
	g := pullsOnly(t, pull12)
	path := historyPath(t)
	dataOf(path).write(t, PullCommitsFile, pullCommitsHeader)
	if err := os.Chmod(filepath.Join(filepath.Dir(path), PullCommitsFile), 0o400); err != nil {
		t.Fatal(err)
	}
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if !errors.Is(r.err, ErrFailed) || !strings.Contains(r.stderr, PullCommitsFile) {
		t.Errorf("want ErrFailed and stderr naming %s, got %v, %q", PullCommitsFile, r.err, r.stderr)
	}
	dataOf(path).want(t, "pulls.csv", "")
	dataOf(path).want(t, "pulls_read.csv", "")
}

// TestTheFirstCommitTimeIsTheEarliestAuthorDateNotTheFirstOfTheList: a
// rebase can put an older commit later in the list (forsgren#255, step 2).
func TestTheFirstCommitTimeIsTheEarliestAuthorDateNotTheFirstOfTheList(t *testing.T) {
	at := func(day int) time.Time { return time.Date(2026, 9, day, 10, 0, 0, 0, time.UTC) }
	listed := []github.PullCommit{{SHA: shaD, AuthoredAt: at(22)}, {SHA: shaE, AuthoredAt: at(20)},
		{SHA: shaB, AuthoredAt: at(21)}}
	if got := earliestAuthored(listed); !got.Equal(at(20)) {
		t.Errorf("want %v, got %v", at(20), got)
	}
	if got := earliestAuthored(nil); !got.IsZero() {
		t.Errorf("want no time for no commit, got %v", got)
	}
}
