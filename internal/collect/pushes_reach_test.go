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
// oldest push being the oldest stored one cuts nothing. Either way one request
// is made, once: a second run asks nothing.
func TestTheReachCheckMarksAnAlreadyCutRepositoryOnly(t *testing.T) {
	for name, c := range map[string]struct{ oldest, cut string }{
		"already cut": {pushTime0, pushesCutHdr + "acme/app," + pushTime1 + "\n"},
		"complete":    {pushTime1, ""},
	} {
		t.Run(name, func(t *testing.T) {
			g, path := storedPushRun(t)
			g.bodies[oldestFirstPath] = list(activityOf("push", c.oldest, shaC, shaA))
			for range 2 {
				if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
					t.Fatal(r.err)
				}
			}
			wantOldestFirstRequests(t, g, 1)
			dataOf(path).want(t, PushesCutFile, c.cut)
			dataOf(path).want(t, PushesCheckedFile, pushesCheckedNow)
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

// TestAFirstReadThatEndsIsCheckedWithoutARequest: a first read that reached
// the end of the list needs no check.
func TestAFirstReadThatEndsIsCheckedWithoutARequest(t *testing.T) {
	g := pushesOnly(t, activityOf("push", pushTime1, shaA, shaB))
	g.bodies[comparePath(shaA, shaB)] = chain(shaA, shaB)
	path := historyPath(t)
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatal(r.err)
	}
	wantOldestFirstRequests(t, g, 0)
	dataOf(path).want(t, PushesCheckedFile, pushesCheckedNow)
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
