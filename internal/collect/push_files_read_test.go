package collect

import (
	"fmt"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// The pushed commits in the commit files read (forsgren#589, step 4): for a
// repository with paths, after the deployed commits come the commits of
// push_commits.csv, first-parent and branch commits alike, each SHA once
// whatever brought it, the newest push first and then the newest author
// date, inside the one cap of a run. push_files_filled.csv notes the
// repository when a run leaves no pushed commit unread, a commit GitHub no
// longer has excepted, and loses its line when a run leaves one unread.

// pushed is a made-up SHA of a pushed commit.
func pushed(n int) string { return fmt.Sprintf("%040x", 0xd00+n) }

// pushedCommit is the line of sha brought by the push whose after SHA is
// after, authored at, first-parent or not.
func pushedCommit(after, sha string, authored time.Time, firstParent bool) history.PushCommit {
	return history.PushCommit{Repository: "acme/app", After: after, SHA: sha, AuthoredAt: authored,
		FirstParent: firstParent, Parents: 1}
}

// storePushes stores pushes of acme/app, each a push from shaA to its after
// SHA at its time, and the commits they brought.
func storePushes(t *testing.T, path string, at map[string]time.Time, commits ...history.PushCommit) {
	t.Helper()
	var pushes []history.Push
	for after, when := range at {
		pushes = append(pushes, history.Push{Repository: "acme/app", PushedAt: when, Before: shaA, After: after,
			Kind: history.PushKindPush, Commits: 1})
	}
	if _, err := history.AppendPushCommits(pushCommitsPath(path), commits); err != nil {
		t.Fatal(err)
	}
	if _, err := history.AppendPushes(pushesPath(path), pushes); err != nil {
		t.Fatal(err)
	}
}

// pushCommitsPath and pushesPath are the push files next to the history.
func pushCommitsPath(path string) string { return filepath.Join(filepath.Dir(path), PushCommitsFile) }
func pushesPath(path string) string      { return filepath.Join(filepath.Dir(path), PushesFile) }

// deployedAndPushed stores, beside the deployed commits A and B, an older push
// (after pushed(1)) that brought pushed(1) and the deployed B, and a newer
// one (after pushed(3)) that brought the branch commit pushed(2) and pushed(3),
// and pushed(1) again, which stays at its earlier push, and gives every
// pushed commit its files on the fake.
func deployedAndPushed(t *testing.T) (*gitHub, string) {
	t.Helper()
	g, path := storedCommits(t)
	storePushes(t, path, map[string]time.Time{pushed(1): at(10, 9, 0), pushed(3): at(15, 9, 0)},
		pushedCommit(pushed(1), pushed(1), at(9, 9, 0), true),
		pushedCommit(pushed(1), shaB, at(21, 9, 0), true),
		pushedCommit(pushed(3), pushed(2), at(8, 9, 0), false),
		pushedCommit(pushed(3), pushed(3), at(14, 9, 0), true),
		pushedCommit(pushed(3), pushed(1), at(9, 9, 0), false))
	g.bodies[filesPath(shaB)] = filesBody("api/b.go")
	g.bodies[filesPath(shaA)] = filesBody("api/a.go")
	for n := 1; n <= 3; n++ {
		g.bodies[filesPath(pushed(n))] = filesBody("api/p.go")
	}
	return g, path
}

// TestThePushedCommitsAreReadAfterTheDeployedOnesNewestPushFirst: the
// deployed commits first, then the newer push's commits, newest author date
// first and its branch commit too, then the older push's own commit; B, both
// deployed and pushed, is asked once; both marks are noted.
func TestThePushedCommitsAreReadAfterTheDeployedOnesNewestPushFirst(t *testing.T) {
	g, path := deployedAndPushed(t)
	if r := g.collect(t, shop(withPaths()), path, github.DefaultMaxPages); r.err != nil {
		t.Fatalf("want no error, got %v (stderr %q)", r.err, r.stderr)
	}
	g.wantAsked(t, shaB, shaA, pushed(3), pushed(2), pushed(1))
	dataOf(path).want(t, CommitFilesFilledFile, commitFilesFilledNow)
	dataOf(path).want(t, PushFilesFilledFile, pushFilesFilledNow)
}

// TestAPushedCommitGitHubNoLongerHasIsNamedAndDoesNotHoldTheMark: a 404 of a
// pushed commit (pushed away) is named on stderr and left without lines, and
// both marks are noted all the same.
func TestAPushedCommitGitHubNoLongerHasIsNamedAndDoesNotHoldTheMark(t *testing.T) {
	g, path := deployedAndPushed(t)
	delete(g.bodies, filesPath(pushed(2)))
	r := g.collect(t, shop(withPaths()), path, github.DefaultMaxPages)
	if r.err != nil || !strings.Contains(r.stderr, "acme/app: commit "+pushed(2)+": not found") {
		t.Fatalf("want stderr to name the missing commit and no error, got %v (stderr %q)", r.err, r.stderr)
	}
	g.wantAsked(t, shaB, shaA, pushed(3), pushed(2), pushed(1))
	dataOf(path).want(t, CommitFilesFilledFile, commitFilesFilledNow)
	dataOf(path).want(t, PushFilesFilledFile, pushFilesFilledNow)
}

// TestTheDeployedAndThePushedCommitsShareTheCapOfARun: with the cap's worth of
// deployed commits the pushed one waits for the next run; the deployed mark
// is noted, the push mark only once the next run read the pushed commit.
func TestTheDeployedAndThePushedCommitsShareTheCapOfARun(t *testing.T) {
	g, path, _ := manyCommits(t, capOfARun)
	storePushes(t, path, map[string]time.Time{pushed(1): at(10, 9, 0)},
		pushedCommit(pushed(1), pushed(1), at(9, 9, 0), true))
	g.bodies[filesPath(pushed(1))] = filesBody("api/p.go")
	if r := g.collect(t, shop(withPaths()), path, github.DefaultMaxPages); r.err != nil {
		t.Fatal(r.err)
	}
	if asked := g.filesAsked(); len(asked) != capOfARun || strings.Contains(strings.Join(asked, " "), pushed(1)) {
		t.Errorf("want the %d deployed commits asked and not the pushed one, got %d", capOfARun, len(asked))
	}
	g.wantReportOf(t, Report{FilesCapped: []string{"acme/app"}})
	dataOf(path).want(t, CommitFilesFilledFile, commitFilesFilledNow)
	dataOf(path).want(t, PushFilesFilledFile, "")
	g.requests = nil
	if r := g.collect(t, shop(withPaths()), path, github.DefaultMaxPages); r.err != nil {
		t.Fatal(r.err)
	}
	g.wantAsked(t, pushed(1))
	dataOf(path).want(t, PushFilesFilledFile, pushFilesFilledNow)
}

// TestARunThatLeavesAPushedCommitUnreadTakesThePushMarkAway: older pushed
// commits stored later (the fill of the older pushes) are unread again; a
// run the budget stops before them removes the repository's push mark, so
// the page says its first commit is still being read.
func TestARunThatLeavesAPushedCommitUnreadTakesThePushMarkAway(t *testing.T) {
	g, path := deployedAndPushed(t)
	dataOf(path).write(t, PushFilesFilledFile, pushFilesFilledNow)
	g.left[filesPath(pushed(3))] = 250
	r := g.collect(t, shop(withPaths()), path, github.DefaultMaxPages)
	if r.err != nil || !strings.Contains(r.stderr, "the commit files were cut short") {
		t.Fatalf("want the files cut short and no error, got %v (stderr %q)", r.err, r.stderr)
	}
	dataOf(path).want(t, CommitFilesFilledFile, commitFilesFilledNow)
	dataOf(path).want(t, PushFilesFilledFile, "# forsgren push files filled v1\nrepository,filled_at\n")
}

// TestARepositoryWithoutPathsAsksForNoPushedCommit: no request, no mark.
func TestARepositoryWithoutPathsAsksForNoPushedCommit(t *testing.T) {
	g, path := deployedAndPushed(t)
	if r := g.collect(t, shop(withoutPaths()), path, github.DefaultMaxPages); r.err != nil {
		t.Fatal(r.err)
	}
	g.wantAsked(t)
	dataOf(path).want(t, PushFilesFilledFile, "")
}
