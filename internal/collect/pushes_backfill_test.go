package collect

import (
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// The push fill (forsgren#583, step 2): a repository with a line in
// pushes_cut.csv reads its older pushes, newest first, a page at a time
// after GitHub's cursor, which pushes_fill.csv keeps, up to the page cap per
// run; each push is compared and stored as a new one.

const (
	pushTimeA     = "2026-09-10T10:00:00Z"
	pushTimeB     = "2026-09-05T10:00:00Z"
	pushesFillHdr = "# forsgren pushes fill v1\nrepository,filled_at,cursor\n"
)

// cutPushRun is an installation whose acme/app read was cut at its one stored
// push (pushTime1); the activity list holds it, then after cursor c1 a push
// at pushTimeA, then after c2 one at pushTimeB, where the list ends.
func cutPushRun(t *testing.T) (*gitHub, string) {
	t.Helper()
	g, path := storedPushRun(t)
	dataOf(path).write(t, PushesCutFile, pushesCutHdr+"acme/app,"+pushTime1+"\n")
	g.bodies[activityPath] = list(activityOf("push", pushTime1, shaA, shaB))
	g.after[activityPath] = "c1"
	g.bodies[activityPath+afterKey("c1")] = list(activityOf("push", pushTimeA, shaC, shaA))
	g.after[activityPath+afterKey("c1")] = "c2"
	g.bodies[activityPath+afterKey("c2")] = list(activityOf("push", pushTimeB, shaD, shaC))
	g.bodies[comparePath(shaC, shaA)] = chain(shaC, shaA)
	g.bodies[comparePath(shaD, shaC)] = chain(shaD, shaC)
	return g, path
}

// TestTheFillReadsOlderPushesOverRunsWithTheCursor: with a page cap of 2, the
// first run reads the top page (only stored pushes) and the page after c1,
// stores the push at pushTimeA and keeps c2; the second run asks for the page
// after c2 alone and stores the push at pushTimeB. The cut moves to the
// oldest push read, and nothing is stored twice.
func TestTheFillReadsOlderPushesOverRunsWithTheCursor(t *testing.T) {
	g, path := cutPushRun(t)
	runOK(t, g, path, 2)
	data := dataOf(path)
	data.want(t, PushesFillFile, pushesFillHdr+"acme/app,2026-10-01T00:00:00Z,c2\n")
	data.want(t, PushesCutFile, pushesCutHdr+"acme/app,"+pushTimeA+"\n")
	before := len(g.seen(activityPath))
	runOK(t, g, path, 2)
	fill := g.seen(activityPath)[before:]
	if strings.Contains(strings.Join(fill, " "), "after=c1") || !strings.Contains(strings.Join(fill, " "), "after=c2") {
		t.Errorf("want the second run to ask for the page after c2 only, got %v", fill)
	}
	data.want(t, PushesFile, pushesHeader+linePush(pushTime1, shaA, shaB, "push", "false", "1")+
		linePush(pushTimeA, shaC, shaA, "push", "false", "1")+linePush(pushTimeB, shaD, shaC, "push", "false", "1"))
	data.want(t, PushesCutFile, pushesCutHdr+"acme/app,"+pushTimeB+"\n")
	if got := strings.Count(readFileIn(t, path, PushCommitsFile), "\nacme/app,"); got != 2 {
		t.Errorf("want one push commit line per filled push, got %d", got)
	}
}

// TestABudgetStopInTheFillKeepsTheCursorOfItsPage: the budget runs out on the
// page after c1, before its push is compared: nothing of it is stored, the
// cursor stays c1, the report names the fill cut, and the next run reads that
// page again (and the next one, within its cap of 2) and stores the pushes.
func TestABudgetStopInTheFillKeepsTheCursorOfItsPage(t *testing.T) {
	g, path := cutPushRun(t)
	g.left[activityPath+afterKey("c1")] = 100
	runOK(t, g, path, 2)
	data := dataOf(path)
	data.want(t, PushesFillFile, pushesFillHdr+"acme/app,2026-10-01T00:00:00Z,c1\n")
	data.want(t, PushesFile, pushesHeader+linePush(pushTime1, shaA, shaB, "push", "false", "1"))
	if len(g.report.PushesFillCut) != 1 {
		t.Errorf("want the fill cut reported, got %+v", g.report)
	}
	delete(g.left, activityPath+afterKey("c1"))
	before := len(g.seen(activityPath))
	runOK(t, g, path, 2)
	if fill := g.seen(activityPath)[before:]; len(fill) != 3 || !strings.Contains(fill[1], "after=c1") {
		t.Errorf("want the push read, then the page after c1 again and the one after c2, got %v", fill)
	}
	data.want(t, PushesFile, pushesHeader+linePush(pushTime1, shaA, shaB, "push", "false", "1")+
		linePush(pushTimeA, shaC, shaA, "push", "false", "1")+linePush(pushTimeB, shaD, shaC, "push", "false", "1"))
}

// TestTheFillStopsAtHistoryDays: a push older than history_days back is
// neither compared nor stored, and the fill ends there.
func TestTheFillStopsAtHistoryDays(t *testing.T) {
	g, path := cutPushRun(t)
	cfg := shop(production)
	cfg.HistoryDays = 25
	if r := g.collect(t, cfg, path, 10); r.err != nil {
		t.Fatal(r.err)
	}
	data := dataOf(path)
	data.want(t, PushesFile, pushesHeader+linePush(pushTime1, shaA, shaB, "push", "false", "1")+
		linePush(pushTimeA, shaC, shaA, "push", "false", "1"))
	if len(g.seen(comparePath(shaD, shaC))) != 0 {
		t.Error("want the push before history_days not compared")
	}
}

// TestARepositoryWithoutACutLineIsNotFilled: no line in pushes_cut.csv, no
// fill request and no fill file.
func TestARepositoryWithoutACutLineIsNotFilled(t *testing.T) {
	g, path := storedPushRun(t)
	dataOf(path).write(t, PushesCheckedFile, pushesCheckedNow)
	runOK(t, g, path, 10)
	dataOf(path).want(t, PushesFillFile, "")
	if got := g.seen(activityPath); len(got) != 1 {
		t.Errorf("want the push read alone, got %v", got)
	}
}

// runOK runs collect of acme/app's production deployments with a page cap of
// pages and fails on an error.
func runOK(t *testing.T, g *gitHub, path string, pages int) {
	t.Helper()
	if r := g.collect(t, shop(production), path, pages); r.err != nil {
		t.Fatalf("want no error, got %v (stderr %q)", r.err, r.stderr)
	}
}

// readFileIn is the content of the file name next to the history at path.
func readFileIn(t *testing.T, path, name string) string {
	t.Helper()
	raw, err := os.ReadFile(filepath.Clean(filepath.Join(filepath.Dir(path), name)))
	if err != nil {
		t.Fatal(err)
	}
	return string(raw)
}

// TestARefusedFillWritesTheDeniedMark: a 403 on a fill page writes the
// pushes denied mark, as the push read does, keeps the cursor and fails
// nothing.
func TestARefusedFillWritesTheDeniedMark(t *testing.T) {
	g, path := cutPushRun(t)
	g.bodies[activityPath+afterKey("c1")] = `{"message":"Resource not accessible by integration"}`
	g.status[activityPath+afterKey("c1")] = http.StatusForbidden
	runOK(t, g, path, 2)
	dataOf(path).want(t, PushesDeniedFile, pushesDeniedNow)
	dataOf(path).want(t, PushesFillFile, pushesFillHdr+"acme/app,2026-10-01T00:00:00Z,c1\n")
}
