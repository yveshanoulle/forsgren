package collect

import (
	"net/http"
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/github"
)

// The one-time reach check (forsgren#583, step 1): a repository whose stored
// pushes have no line in pushes_cut.csv and that was not checked yet gets one
// request of the activity list oldest first; an older push there than the
// oldest stored one writes the cut line at the oldest stored push.

const (
	// oldestFirstPath is the key of the activity list read oldest first.
	oldestFirstPath  = activityPath + oldestFirst
	pushesCheckedHdr = "# forsgren pushes checked v1\nrepository,checked_at\n"
	// pushesCheckedNow is the checked file after a run that checked acme/app.
	pushesCheckedNow = pushesCheckedHdr + "acme/app,2026-10-01T00:00:00Z\n"
	// pushTime0 is a push older than every stored one.
	pushTime0 = "2026-03-01T10:00:00Z"
)

// storedPushRun is a run of an installation that read acme/app's pushes
// before: one push stored at pushTime1, its read mark set, and nothing new
// in the activity list.
func storedPushRun(t *testing.T) (*gitHub, string) {
	t.Helper()
	g := pushesOnly(t)
	path := historyPath(t)
	data := dataOf(path)
	data.write(t, PushesFile, pushesHeader+linePush(pushTime1, shaA, shaB, "push", "false", "1"))
	data.write(t, PushesReadFile, pushesReadHdr+"acme/app,2026-09-30T00:00:00Z\n")
	return g, path
}

// TestTheReachCheckMarksAnAlreadyCutRepositoryOnly: GitHub holding a push
// older than the oldest stored one means the read was cut before
// pushes_cut.csv existed, and the cut line is the oldest stored push; GitHub's
// oldest push being the oldest stored one, after the creation of the branch,
// cuts nothing. Either way one request is made, once: a second run asks
// nothing. (The page cap of 1 keeps the fill of a cut one at its top page.)
func TestTheReachCheckMarksAnAlreadyCutRepositoryOnly(t *testing.T) {
	creation := activityOf("branch_creation", "2026-03-01T09:00:00Z", shaE, shaC)
	for name, c := range map[string]struct {
		oldest []string
		cut    string
	}{
		"already cut": {[]string{activityOf("push", pushTime0, shaC, shaA)}, pushesCutHdr + "acme/app," + pushTime1 + "\n"},
		"complete":    {[]string{creation, activityOf("push", pushTime1, shaA, shaB)}, ""},
	} {
		t.Run(name, func(t *testing.T) {
			g, path := storedPushRun(t)
			g.bodies[oldestFirstPath] = list(c.oldest...)
			g.after[activityPath] = "c1"
			runOK(t, g, path, 1)
			dataOf(path).want(t, PushesCutFile, c.cut)
			dataOf(path).want(t, PushesCheckedFile, pushesCheckedNow)
			runOK(t, g, path, 1)
			wantOldestFirstRequests(t, g, 1)
		})
	}
}

// TestAFailingReachCheckWritesNothing: an error answer leaves the repository
// unchecked and uncut for the next run, and fails nothing.
func TestAFailingReachCheckWritesNothing(t *testing.T) {
	g, path := storedPushRun(t)
	g.bodies[oldestFirstPath] = `{"message":"boom"}`
	g.status[oldestFirstPath] = http.StatusInternalServerError
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatalf("want the run not failed, got %v", r.err)
	}
	dataOf(path).want(t, PushesCutFile, "")
	dataOf(path).want(t, PushesCheckedFile, "")
}

// TestAFirstReadThatEndsIsCheckedWithOneRequest (forsgren#583, step 3): a
// first read that ended by itself may have reached GitHub's end of the list,
// so it is checked once as well, over the pushes it stored: a list that does
// not start with the creation of the branch notes GitHub's end.
func TestAFirstReadThatEndsIsCheckedWithOneRequest(t *testing.T) {
	g := pushesOnly(t, activityOf("push", pushTime1, shaA, shaB))
	g.bodies[comparePath(shaA, shaB)] = chain(shaA, shaB)
	g.bodies[oldestFirstPath] = list(activityOf("push", pushTime1, shaA, shaB))
	path := historyPath(t)
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatal(r.err)
	}
	wantOldestFirstRequests(t, g, 1)
	dataOf(path).want(t, PushesCheckedFile, pushesCheckedNow)
	dataOf(path).want(t, PushesGitHubEndFile, pushesGitHubEndHdr+"acme/app,"+pushTime1+"\n")
}

// wantOldestFirstRequests fails unless the activity list was read oldest
// first n times.
func wantOldestFirstRequests(t *testing.T, g *gitHub, n int) {
	t.Helper()
	asc := 0
	for _, r := range g.seen(activityPath) {
		if hasDirectionAsc(r) {
			asc++
		}
	}
	if asc != n {
		t.Errorf("want %d oldest-first requests, got %d of %v", n, asc, g.seen(activityPath))
	}
}

// hasDirectionAsc says whether the request URI r asks for the list oldest first.
func hasDirectionAsc(r string) bool { return strings.Contains(r, "direction=asc") }

// TestTheReachCheckNotesGitHubsEnd (forsgren#583, step 3): GitHub's oldest
// push is the oldest stored one, but the list does not start with the
// creation of the branch and that push is within history_days: GitHub keeps
// no older activity, which the check notes; with the creation first it notes
// nothing but the check.
func TestTheReachCheckNotesGitHubsEnd(t *testing.T) {
	for name, c := range map[string]struct{ first, end string }{
		"no creation": {"", pushesGitHubEndHdr + "acme/app," + pushTime1 + "\n"},
		"creation":    {activityOf("branch_creation", "2026-09-19T10:00:00Z", shaE, shaA), ""},
	} {
		t.Run(name, func(t *testing.T) {
			g, path := storedPushRun(t)
			items := []string{activityOf("push", pushTime1, shaA, shaB)}
			if c.first != "" {
				items = append([]string{c.first}, items...)
			}
			g.bodies[oldestFirstPath] = list(items...)
			runOK(t, g, path, 10)
			dataOf(path).want(t, PushesGitHubEndFile, c.end)
			dataOf(path).want(t, PushesCheckedFile, pushesCheckedNow)
		})
	}
}
