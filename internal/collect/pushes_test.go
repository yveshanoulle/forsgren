package collect

import (
	"errors"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/github"
)

// The pushes to the main branch of each repository (forsgren#397, step 2).

const (
	activityPath  = "/repos/acme/app/activity"
	pushesHeader  = "# forsgren pushes v1\nrepository,pushed_at,before,after,kind,bot,commits\n"
	pushesReadHdr = "# forsgren pushes read v1\nrepository,read_at\n"
	// pushesReadNow is the pushes read file after a run that moved acme/app's
	// mark to now.
	pushesReadNow = pushesReadHdr + "acme/app,2026-10-01T00:00:00Z\n"
	pushesDeniedH = "# forsgren pushes denied v1\nrepository,denied_at\n"
	// pushesDeniedNow is the pushes denied file after a run that was refused.
	pushesDeniedNow = pushesDeniedH + "acme/app,2026-10-01T00:00:00Z\n"
)

// activityOf is one item of GitHub's activity list: kind, time, the two
// tips and the actor's JSON value (a person unless said otherwise).
func activityOf(kind, when, before, after string) string {
	return activityBy(kind, when, before, after, `{"login": "someone", "type": "User"}`)
}

// activityBy is activityOf with the actor JSON value actor.
func activityBy(kind, when, before, after, actor string) string {
	return fmt.Sprintf(`{"id": 1, "before": %q, "after": %q, "ref": "refs/heads/main", "timestamp": %q, `+
		`"activity_type": %q, "actor": %s}`, before, after, when, kind, actor)
}

// pushesOnly is a fake GitHub with no deployments, issues or pull requests,
// whose activity list for acme/app is items, newest first.
func pushesOnly(t *testing.T, items ...string) *gitHub {
	t.Helper()
	g := issuesOnly(t)
	g.bodies[activityPath] = list(items...)
	return g
}

// chain is a comparison whose commits are shas, oldest first, each with the
// one before as its parent and the first with parent first.
func chain(first string, shas ...string) string {
	commits := make([]lineage, 0, len(shas))
	parent := first
	for i, sha := range shas {
		commits = append(commits, lineage{authoredBy{authored{sha, at(20, 8+i, 0)}, ""}, []string{parent}, ""})
		parent = sha
	}
	return comparisonOf("ahead", len(shas), commits...)
}

// linePush is the pushes.csv line of a push of acme/app at when.
func linePush(when, before, after, kind, bot, commits string) string {
	return fmt.Sprintf("acme/app,%s,%s,%s,%s,%s,%s\n", when, before, after, kind, bot, commits)
}

const pushCommitsHeader = "# forsgren push commits v1\nrepository,after,sha,author,authored_at\n"

// linePC is the push_commits.csv line of the commit sha of the push of
// acme/app that ended at after.
func linePC(after, sha, author, authored string) string {
	return fmt.Sprintf("acme/app,%s,%s,%s,%s\n", after, sha, author, authored)
}

const (
	pushTime1 = "2026-09-20T10:00:00Z"
	pushTime2 = "2026-09-21T10:00:00Z"
)

// TestCollectStoresEachPushWithTheCommitsItAddedToTheFirstParentChain
// (forsgren#397, step 2): a push and a pull request merge are stored with
// their time, tips, kind, whether a bot made them, and the number of commits
// the push added to the first-parent chain, counted from the compare of
// before...after: three commits of a straight push are 3, a merge commit
// that brought a branch in is 1. The mark moves to now, and the line counts
// the pushes.
func TestCollectStoresEachPushWithTheCommitsItAddedToTheFirstParentChain(t *testing.T) {
	g := pushesOnly(t,
		activityBy("pr_merge", pushTime2, shaD, shaF, `{"login": "robot[bot]", "type": "Bot"}`),
		activityOf("push", pushTime1, shaA, shaD))
	g.bodies[comparePath(shaA, shaD)] = chain(shaA, shaB, shaC, shaD)
	g.bodies[comparePath(shaD, shaF)] = comparisonOf("ahead", 2,
		lineage{authoredBy{authored{shaE, at(21, 8, 0)}, ""}, []string{shaD}, ""},
		lineage{authoredBy{authored{shaF, at(21, 9, 0)}, "acme-dev"}, []string{shaD, shaE}, ""})
	path := historyPath(t)
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	wantStdout(t, r, "acme/app: 0 new, 0 skipped (not final), 0 commits, 2 pushes\n")
	data := dataOf(path)
	data.want(t, PushesFile, pushesHeader+linePush(pushTime1, shaA, shaD, "push", "false", "3")+
		linePush(pushTime2, shaD, shaF, "pr_merge", "true", "1"))
	data.want(t, PushesReadFile, pushesReadNow)
	data.want(t, PushesDeniedFile, "")
	data.want(t, PushCommitsFile, pushCommitsHeader+
		linePC(shaD, shaB, "", "2026-09-20T08:00:00Z")+linePC(shaD, shaC, "", "2026-09-20T09:00:00Z")+
		linePC(shaD, shaD, "", "2026-09-20T10:00:00Z")+linePC(shaF, shaF, "acme-dev", "2026-09-21T09:00:00Z"))
	if got := g.seen(activityPath); len(got) != 1 || !strings.Contains(got[0], "ref=refs%2Fheads%2Fmain") {
		t.Errorf("want one read of main's activity, got %v", got)
	}
}

// TestAPushWhoseCompareFailsIsStoredWithNoCommitCount: a compare that
// GitHub cut, answers with a head that is no descendant, or cannot find a
// commit for, leaves the commits column empty and says so on stderr, naming
// the repository and the tips; it never guesses a number and never fails the
// repository. A comparison whose chain does not reach the push's tip is no
// number either.
func TestAPushWhoseCompareFailsIsStoredWithNoCommitCount(t *testing.T) {
	g := pushesOnly(t,
		activityOf("push", "2026-09-23T10:00:00Z", shaE, shaF),
		activityOf("push", "2026-09-22T10:00:00Z", shaC, shaE),
		activityOf("push", pushTime2, shaB, shaC),
		activityOf("push", pushTime1, shaA, shaB))
	g.bodies[comparePath(shaA, shaB)] = comparisonOf("ahead", 5,
		lineage{authoredBy{authored{shaB, at(20, 8, 0)}, ""}, []string{shaA}, ""})
	g.bodies[comparePath(shaB, shaC)] = comparisonOf("diverged", 1)
	// shaC...shaE has no compare answer: GitHub's 404.
	g.bodies[comparePath(shaE, shaF)] = chain(shaE, shaD)
	path := historyPath(t)
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	wantStdout(t, r, "acme/app: 0 new, 0 skipped (not final), 0 commits, 4 pushes\n")
	dataOf(path).want(t, PushesFile, pushesHeader+
		linePush(pushTime1, shaA, shaB, "push", "false", "")+
		linePush(pushTime2, shaB, shaC, "push", "false", "")+
		linePush("2026-09-22T10:00:00Z", shaC, shaE, "push", "false", "")+
		linePush("2026-09-23T10:00:00Z", shaE, shaF, "push", "false", ""))
	for _, want := range []string{"acme/app", shaB, shaC, shaE, shaF, "commits column stays empty"} {
		if !strings.Contains(r.stderr, want) {
			t.Errorf("want stderr to hold %q, got %q", want, r.stderr)
		}
	}
}

// TestAForcePushIsNotedWithoutACompare: a force push is stored with its
// kind and no commit count, asks for no compare (its before is not an
// ancestor), and stderr names it.
func TestAForcePushIsNotedWithoutACompare(t *testing.T) {
	g := pushesOnly(t, activityOf("force_push", pushTime1, shaA, shaB))
	path := historyPath(t)
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	wantStdout(t, r, "acme/app: 0 new, 0 skipped (not final), 0 commits, 1 pushes\n")
	dataOf(path).want(t, PushesFile, pushesHeader+linePush(pushTime1, shaA, shaB, "force_push", "false", ""))
	if got := g.seen("/repos/acme/app/compare/"); len(got) != 0 {
		t.Errorf("want no compare for a force push, got %v", got)
	}
	if !strings.Contains(r.stderr, "force push") || !strings.Contains(r.stderr, shaB) {
		t.Errorf("want stderr to name the force push, got %q", r.stderr)
	}
}

// TestAStoredPushIsNeitherStoredNorComparedAgain: a push already in
// pushes.csv (repository, after SHA and time) costs no compare and its line
// stays as it is.
func TestAStoredPushIsNeitherStoredNorComparedAgain(t *testing.T) {
	g := pushesOnly(t, activityOf("push", pushTime1, shaA, shaB))
	path := historyPath(t)
	data := dataOf(path)
	stored := pushesHeader + linePush(pushTime1, shaA, shaB, "push", "false", "7")
	data.write(t, PushesFile, stored)
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	wantStdout(t, r, "acme/app: 0 new, 0 skipped (not final), 0 commits\n")
	data.want(t, PushesFile, stored)
	if got := g.seen("/repos/acme/app/compare/"); len(got) != 0 {
		t.Errorf("want no compare for a stored push, got %v", got)
	}
}

// TestThePushesAreReadFromWhereTheLastReadEnded: the read starts at the mark
// less a day, never before history_days back, and at history_days back when
// there is no mark.
func TestThePushesAreReadFromWhereTheLastReadEnded(t *testing.T) {
	for _, c := range []readWindow{
		{"no mark reads history_days back", "", "2025-10-02T00:00:00Z", true},
		{"before history_days", "", "2025-09-30T00:00:00Z", false},
		{"a mark less a day", "2026-09-25T08:00:00Z", "2026-09-24T09:00:00Z", true},
		{"before a mark less a day", "2026-09-25T08:00:00Z", "2026-09-24T07:00:00Z", false},
		{"a mark older than history_days", "2024-01-01T00:00:00Z", "2025-09-30T00:00:00Z", false},
	} {
		t.Run(c.name, c.check)
	}
}

// readWindow is a run with the pushes read mark before it (empty for none)
// and one push of acme/app at pushed, and whether that push is stored.
type readWindow struct {
	name, mark, pushed string
	stored             bool
}

// check fails unless the run stores the push exactly when c says, and moves
// the mark to now.
func (c readWindow) check(t *testing.T) {
	g := pushesOnly(t, activityOf("push", c.pushed, shaA, shaB))
	g.bodies[comparePath(shaA, shaB)] = chain(shaA, shaB)
	path := historyPath(t)
	data := dataOf(path)
	if c.mark != "" {
		data.write(t, PushesReadFile, pushesReadHdr+"acme/app,"+c.mark+"\n")
	}
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatalf("want no error, got %v (stderr %q)", r.err, r.stderr)
	}
	want := pushesHeader
	if c.stored {
		want += linePush(c.pushed, shaA, shaB, "push", "false", "1")
	}
	data.want(t, PushesFile, want)
	data.want(t, PushesReadFile, pushesReadNow)
}

// TestAMissingContentsPermissionNeverFailsThePushRead: a 403 on the activity
// list stores no push and moves no mark, stderr names the missing
// permission, the repository's line in pushes_denied.csv says so, and the
// repository does not fail. A read that works removes the line.
func TestAMissingContentsPermissionNeverFailsThePushRead(t *testing.T) {
	g := pushesOnly(t)
	g.deny(activityPath)
	path := historyPath(t)
	data := dataOf(path)
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	wantStdout(t, r, "acme/app: 0 new, 0 skipped (not final), 0 commits\n")
	data.want(t, PushesFile, pushesHeader)
	data.want(t, PushesReadFile, "")
	data.want(t, PushesDeniedFile, pushesDeniedNow)
	data.wantNoToken(t, PushesDeniedFile)
	if !strings.Contains(r.stderr, "pushes are not readable") || !strings.Contains(r.stderr, "Contents: Read") {
		t.Errorf("want stderr to name the missing permission, got %q", r.stderr)
	}
	g.status = map[string]int{}
	g.bodies[activityPath] = list()
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatalf("want no error, got %v", r.err)
	}
	data.want(t, PushesDeniedFile, pushesDeniedH)
	data.want(t, PushesReadFile, pushesReadNow)
}

// TestAnotherPushReadErrorFailsTheRepositoryAndLeavesTheMarks: a server
// error on the activity list fails the repository, moves no mark and leaves
// pushes_denied.csv as it was.
func TestAnotherPushReadErrorFailsTheRepositoryAndLeavesTheMarks(t *testing.T) {
	g := pushesOnly(t)
	g.bodies[activityPath] = `{"message": "Server Error"}`
	g.status[activityPath] = http.StatusInternalServerError
	path := historyPath(t)
	data := dataOf(path)
	data.write(t, PushesDeniedFile, pushesDeniedNow)
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if !errors.Is(r.err, ErrFailed) {
		t.Errorf("want the repository failed, got %v (stderr %q)", r.err, r.stderr)
	}
	data.want(t, PushesReadFile, "")
	data.want(t, PushesDeniedFile, pushesDeniedNow)
}

// TestABudgetStopKeepsThePushesReadWholeAndTheMark: when the budget stops the
// compares, the pushes compared are stored, the mark stays, stderr says the
// rest is read again, and the repository does not fail; the next run
// stores the rest.
func TestABudgetStopKeepsThePushesReadWholeAndTheMark(t *testing.T) {
	g := pushesOnly(t,
		activityOf("push", pushTime2, shaB, shaC),
		activityOf("push", pushTime1, shaA, shaB))
	g.bodies[comparePath(shaB, shaC)] = chain(shaB, shaC)
	g.bodies[comparePath(shaA, shaB)] = chain(shaA, shaB)
	g.left[comparePath(shaB, shaC)] = 249
	path := historyPath(t)
	data := dataOf(path)
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if r.err != nil {
		t.Fatalf("want no error, got %v (stderr %q)", r.err, r.stderr)
	}
	data.want(t, PushesFile, pushesHeader+linePush(pushTime2, shaB, shaC, "push", "false", "1"))
	data.want(t, PushesReadFile, "")
	if !strings.Contains(r.stderr, "pushes") || !strings.Contains(r.stderr, "read again") {
		t.Errorf("want stderr to say the pushes are read again, got %q", r.stderr)
	}
	if want := (Report{PushesCut: []string{"acme/app"}, Reset: g.resetAt.UTC()}); !reflect.DeepEqual(g.report, want) {
		t.Errorf("want the report %+v, got %+v", want, g.report)
	}
	g.left = map[string]int{}
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatalf("want no error on the next run, got %v (stderr %q)", r.err, r.stderr)
	}
	data.want(t, PushesFile, pushesHeader+linePush(pushTime2, shaB, shaC, "push", "false", "1")+
		linePush(pushTime1, shaA, shaB, "push", "false", "1"))
	data.want(t, PushesReadFile, pushesReadNow)
}

// TestAnUnreadablePushFileRefusesTheRunBeforeGitHubIsAsked: the pushes file
// and the push commits file (forsgren#397, step 3) alike.
func TestAnUnreadablePushFileRefusesTheRunBeforeGitHubIsAsked(t *testing.T) {
	for file, unknown := range map[string]string{
		PushesFile:      "# forsgren pushes v9\n",
		PushCommitsFile: "# forsgren push commits v9\n",
	} {
		t.Run(file, func(t *testing.T) {
			g := pushesOnly(t)
			path := historyPath(t)
			dataOf(path).write(t, file, unknown)
			r := g.collect(t, shop(production), path, github.DefaultMaxPages)
			if r.err == nil || !strings.Contains(r.err.Error(), file) {
				t.Errorf("want the run refused naming %s, got %v", file, r.err)
			}
			if got := g.seen(""); len(got) != 0 {
				t.Errorf("want GitHub not asked, got %v", got)
			}
		})
	}
}

// TestAPushesFileThatCannotBeWrittenFailsTheRepository: the error names
// pushes.csv and no mark moves.
func TestAPushesFileThatCannotBeWrittenFailsTheRepository(t *testing.T) {
	g := pushesOnly(t, activityOf("push", pushTime1, shaA, shaB))
	g.bodies[comparePath(shaA, shaB)] = chain(shaA, shaB)
	path := historyPath(t)
	dataOf(path).write(t, PushesFile, pushesHeader)
	if err := os.Chmod(filepath.Join(filepath.Dir(path), PushesFile), 0o400); err != nil {
		t.Fatal(err)
	}
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if !errors.Is(r.err, ErrFailed) || !strings.Contains(r.stderr, PushesFile) {
		t.Errorf("want ErrFailed and stderr naming %s, got %v, %q", PushesFile, r.err, r.stderr)
	}
	dataOf(path).want(t, PushesReadFile, "")
}

// TestAPushListCutAtThePageLimitIsNamedAndTheMarkMoves: the list is newest
// first, so the same mark would read the same pages; stderr says older
// pushes may be skipped for good.
func TestAPushListCutAtThePageLimitIsNamedAndTheMarkMoves(t *testing.T) {
	g := pushesOnly(t, activityOf("push", pushTime1, shaA, shaB))
	g.bodies[comparePath(shaA, shaB)] = chain(shaA, shaB)
	g.paged[activityPath] = true
	path := historyPath(t)
	r := g.collect(t, shop(production), path, 1)
	if r.err != nil || !strings.Contains(r.stderr, "push read is incomplete") {
		t.Errorf("want the incomplete read named and no error, got %v, %q", r.err, r.stderr)
	}
	dataOf(path).want(t, PushesReadFile, pushesReadNow)
}

// TestTheFirstParentCountEndsAtARootCommitAndAtACycle: a chain that reaches
// a commit with no parent counts it and stops; a commit that names itself as
// its first parent is counted once; a tip that is not among the commits is
// none.
func TestTheFirstParentCountEndsAtARootCommitAndAtACycle(t *testing.T) {
	root := github.Commit{SHA: shaB}
	loop := github.Commit{SHA: shaC, Parents: []string{shaC}}
	for name, c := range map[string]struct {
		commits []github.Commit
		tip     string
		want    int64
	}{
		"root":      {[]github.Commit{{SHA: shaC, Parents: []string{shaB}}, root}, shaC, 2},
		"cycle":     {[]github.Commit{loop}, shaC, 1},
		"not in it": {[]github.Commit{root}, shaD, 0},
	} {
		if got := int64(len(firstParentChain(c.commits, c.tip))); got != c.want {
			t.Errorf("%s: want %d, got %d", name, c.want, got)
		}
	}
}

// TestThePushesAreReadFromTheRepositorysDefaultBranch (forsgren#397): a
// repository whose default branch is trunk has its activity read for
// refs/heads/trunk, and the repository is asked for its default branch once
// even though the workflow rule asks too.
func TestThePushesAreReadFromTheRepositorysDefaultBranch(t *testing.T) {
	g := pushesOnly(t, activityOf("push", pushTime1, shaA, shaB))
	g.bodies["/repos/acme/app"] = `{"full_name": "acme/app", "default_branch": "trunk"}`
	g.bodies[comparePath(shaA, shaB)] = chain(shaA, shaB)
	path := historyPath(t)
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	wantStdout(t, r, "acme/app: 0 new, 0 skipped (not final), 0 commits, 1 pushes\n")
	if got := g.seen(activityPath); len(got) != 1 || !strings.Contains(got[0], "ref=refs%2Fheads%2Ftrunk") {
		t.Errorf("want one read of trunk's activity, got %v", got)
	}
}

// TestTheDefaultBranchIsAskedOncePerRepositoryAndRun: the workflow rule and
// the push read share one request for it.
func TestTheDefaultBranchIsAskedOncePerRepositoryAndRun(t *testing.T) {
	g := newGitHub(t)
	g.bodies["/repos/acme/app"] = `{"default_branch": "trunk"}`
	g.bodies[runsPath] = runs()
	g.bodies[issuesPath] = list()
	path := historyPath(t)
	r := g.collect(t, shop(repository("acme/app", config.Workflow, "deploy.yml")), path, github.DefaultMaxPages)
	if r.err != nil {
		t.Fatalf("want no error, got %v (stderr %q)", r.err, r.stderr)
	}
	if got := g.seen("/repos/acme/app"); countExactly(got, "/repos/acme/app") != 1 {
		t.Errorf("want the default branch asked once, got %v", got)
	}
}

// countExactly is how many of requests are exactly want.
func countExactly(requests []string, want string) int {
	n := 0
	for _, r := range requests {
		if r == want {
			n++
		}
	}
	return n
}

// TestAPushReadThatCannotAskForTheDefaultBranchFailsTheRepository: no
// fallback to a branch name; nothing is stored and no mark moves.
func TestAPushReadThatCannotAskForTheDefaultBranchFailsTheRepository(t *testing.T) {
	g := pushesOnly(t, activityOf("push", pushTime1, shaA, shaB))
	g.bodies["/repos/acme/app"], g.status["/repos/acme/app"] = `{"message":"Not Found"}`, http.StatusNotFound
	path := historyPath(t)
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if !errors.Is(r.err, ErrFailed) || len(g.seen(activityPath)) != 0 {
		t.Errorf("want the repository failed and no activity read, got %v, %v", r.err, g.seen(activityPath))
	}
	dataOf(path).want(t, PushesReadFile, "")
}
