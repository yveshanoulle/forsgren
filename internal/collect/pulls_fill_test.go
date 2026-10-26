package collect

import (
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/github"
)

// The fill of the commits of the stored merged pull requests (forsgren#470,
// step 1): a pull request stored before pull_commits.csv existed has no
// commit lines, so once per repository each stored pull request whose first
// commit time is real and that has none gets them.

const pullCommitsFilledHeader = "# forsgren pull commits filled v1\nrepository,filled_at\n"

// filledNow is the pull commits filled file after a run that noted acme/app
// as filled now.
const filledNow = pullCommitsFilledHeader + "acme/app,2026-10-01T00:00:00Z\n"

// storedPulls stores pulls.csv with pull 12 (a real first commit time, no
// commit lines), pull 14 (its created time stands in) and pull 15 (a real
// time, whose commit lines are stored) and returns the fake whose commits
// are those of pull 12 alone; nothing else is listed.
func storedPulls(t *testing.T) (*gitHub, string) {
	t.Helper()
	g := pullsOnly(t)
	g.bodies[pull12.commitsPath()] = twoCommits()
	path := historyPath(t)
	data := dataOf(path)
	data.write(t, "pulls.csv", pullsHeader+pull12.line("2026-09-20T10:00:00Z", false)+
		pull14.line("", false)+pull15.line("2026-09-24T10:00:00Z", false))
	data.write(t, PullCommitsFile, pullCommitsHeader+linePullCommit(15, shaD, "acme-dev", "2026-09-24T10:00:00Z"))
	return g, path
}

// TestTheFillReadsTheCommitsOfAStoredPullRequestWithNone: pull 12 gets its
// commit lines, appended after the stored ones; pull 14 (its created time
// stands in) and pull 15 (it has lines) are not asked, and the repository is
// noted as filled.
func TestTheFillReadsTheCommitsOfAStoredPullRequestWithNone(t *testing.T) {
	g, path := storedPulls(t)
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatalf("want no error, got %v (stderr %q)", r.err, r.stderr)
	}
	data := dataOf(path)
	data.want(t, PullCommitsFile, pullCommitsHeader+linePullCommit(15, shaD, "acme-dev", "2026-09-24T10:00:00Z")+
		linePullCommit(12, shaE, "acme-dev", "2026-09-20T10:00:00Z")+linePullCommit(12, shaD, "", "2026-09-21T10:00:00Z"))
	data.want(t, PullCommitsFilledFile, filledNow)
	for _, p := range []pull{pull14, pull15} {
		if got := g.seen(p.commitsPath()); len(got) != 0 {
			t.Errorf("want no commits asked of pull request %d, got %v", p.n, got)
		}
	}
}

// TestTheFillIsDoneOncePerRepository: a second run, after the mark, asks for
// no commits, even of a pull request that still has no lines.
func TestTheFillIsDoneOncePerRepository(t *testing.T) {
	g, path := storedPulls(t)
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatal(r.err)
	}
	asked := len(g.seen(pull12.commitsPath()))
	dataOf(path).write(t, PullCommitsFile, pullCommitsHeader)
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatal(r.err)
	}
	if again := len(g.seen(pull12.commitsPath())); asked != 1 || again != asked {
		t.Errorf("want pull request 12 asked once over two runs, got %d then %d", asked, again)
	}
}

// storedTwo stores pulls 12 and 14, both with a real time and no lines, and
// makes the fake list the commits of both.
func storedTwo(t *testing.T) (*gitHub, string) {
	t.Helper()
	g := pullsOnly(t)
	g.bodies[pull12.commitsPath()] = twoCommits()
	g.bodies[pull14.commitsPath()] = list(commitBy(shaD, "acme-dev", "2026-09-23T10:00:00Z"))
	path := historyPath(t)
	dataOf(path).write(t, "pulls.csv", pullsHeader+pull12.line("2026-09-20T10:00:00Z", false)+
		pull14.line("2026-09-23T10:00:00Z", false))
	return g, path
}

// TestTheFillStopsWithinTheRequestBudgetAndTheNextRunContinues: at the margin
// the pull requests filled whole are stored and the repository is not noted;
// stderr says so, the run does not fail, the report names the repository as
// incomplete for its pull requests, and the next run fills the rest.
func TestTheFillStopsWithinTheRequestBudgetAndTheNextRunContinues(t *testing.T) {
	g, path := storedTwo(t)
	g.left[pull12.commitsPath()] = 251
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if r.err != nil || !strings.Contains(r.stderr, "acme/app: the pull request commits were cut short") {
		t.Errorf("want stderr to say the fill was cut short and no error, got %q, %v", r.stderr, r.err)
	}
	data := dataOf(path)
	data.want(t, PullCommitsFile, twoCommitLines())
	data.want(t, PullCommitsFilledFile, "")
	g.wantReportOf(t, Report{PullFillCut: []string{"acme/app"}, Reset: g.resetAt.UTC()})
	delete(g.left, pull12.commitsPath())
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatal(r.err)
	}
	data.want(t, PullCommitsFile, twoCommitLines()+linePullCommit(14, shaD, "acme-dev", "2026-09-23T10:00:00Z"))
	data.want(t, PullCommitsFilledFile, filledNow)
}

// TestADeniedFillWritesTheDeniedMarkAndNeverFails: a 403 on a pull request's
// commits stores none, notes no fill, names the missing permission, writes
// the repository in pulls_denied.csv and does not fail the run, as the read
// of the pull requests does.
func TestADeniedFillWritesTheDeniedMarkAndNeverFails(t *testing.T) {
	g, path := storedTwo(t)
	g.deny(pull12.commitsPath())
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if r.err != nil || !strings.Contains(r.stderr, "Pull requests: Read") {
		t.Errorf("want stderr to name Pull requests: Read and no error, got %q, %v", r.stderr, r.err)
	}
	data := dataOf(path)
	data.want(t, PullCommitsFilledFile, "")
	data.want(t, PullCommitsFile, pullCommitsHeader)
	data.want(t, PullsDeniedFile,
		"# forsgren pulls denied v2\nrepository,denied_at,token\nacme/app,2026-10-01T00:00:00Z,FORSGREN_TOKEN\n")
}

// TestAFillGitHubAnswersWronglyFailsTheRepositoryAfterStoringWhatItRead: any
// other error fails the repository, the commits read before it are stored,
// and the repository is not noted.
func TestAFillGitHubAnswersWronglyFailsTheRepositoryAfterStoringWhatItRead(t *testing.T) {
	g, path := storedTwo(t)
	g.status[pull14.commitsPath()] = http.StatusInternalServerError
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if !errors.Is(r.err, ErrFailed) {
		t.Errorf("want ErrFailed, got %v (stderr %q)", r.err, r.stderr)
	}
	dataOf(path).want(t, PullCommitsFile, twoCommitLines())
	dataOf(path).want(t, PullCommitsFilledFile, "")
}

// TestAnUnreadableCommitListIsLeftAndTheFillIsNoted: a list that cannot be
// read is named on stderr and left without lines; it does not keep the
// repository from being noted (decision #313).
func TestAnUnreadableCommitListIsLeftAndTheFillIsNoted(t *testing.T) {
	g, path := storedTwo(t)
	g.bodies[pull12.commitsPath()] = `{"message": "not a list"}`
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if r.err != nil || !strings.Contains(r.stderr, unreadableCommits) {
		t.Errorf("want stderr to warn of the unreadable list and no error, got %q, %v", r.stderr, r.err)
	}
	dataOf(path).want(t, PullCommitsFile,
		pullCommitsHeader+linePullCommit(14, shaD, "acme-dev", "2026-09-23T10:00:00Z"))
	dataOf(path).want(t, PullCommitsFilledFile, filledNow)
}

// TestAFillThatCannotBeWrittenFailsTheRepositoryAndNotesNoFill: a
// pull_commits.csv that cannot be written fails the repository, and the
// repository is not noted, so the next run fills again.
func TestAFillThatCannotBeWrittenFailsTheRepositoryAndNotesNoFill(t *testing.T) {
	g, path := storedTwo(t)
	dataOf(path).write(t, PullCommitsFile, pullCommitsHeader)
	if err := os.Chmod(filepath.Join(filepath.Dir(path), PullCommitsFile), 0o400); err != nil {
		t.Fatal(err)
	}
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if !errors.Is(r.err, ErrFailed) || !strings.Contains(r.stderr, PullCommitsFile) {
		t.Errorf("want ErrFailed and stderr naming %s, got %v, %q", PullCommitsFile, r.err, r.stderr)
	}
	dataOf(path).want(t, PullCommitsFilledFile, "")
}
