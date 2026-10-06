package collect

import (
	"path/filepath"
	"strconv"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// Backfilled deployments get their commits (forsgren#66). The stream is four
// successes of acme/app's production, each with the ID 1000 plus its age in
// days: P (5 days old, stored first, with no commits), B (150), A (180) and
// Z (250), and one commit in each comparison of neighbours.
const shaG = "9999999999999999999999999999999999999999"

// backfillGitHub is a fake GitHub that lists P, B, A and Z, newest first,
// and answers the comparisons of neighbours.
func backfillGitHub(t *testing.T) *gitHub {
	t.Helper()
	g := newGitHub(t)
	var listed []string
	for _, d := range []struct {
		age int
		sha string
	}{{5, shaD}, {150, shaC}, {180, shaB}, {250, shaA}} {
		created := ago(d.age).Format(time.RFC3339)
		listed = append(listed, deployment(int64(1000+d.age), d.sha, "deploy", created))
		g.bodies[statusesPath(strconv.Itoa(1000+d.age))] = list(status(1, "success", created))
	}
	g.bodies[deploymentsPath] = list(listed...)
	g.bodies[comparePath(shaB, shaC)] = ahead(authored{shaE, ago(160)}) // A to B
	g.bodies[comparePath(shaC, shaD)] = ahead(authored{shaF, ago(100)}) // B to P
	g.bodies[comparePath(shaA, shaB)] = ahead(authored{shaG, ago(200)}) // Z to A
	return g
}

// backfillRuns stores P, notes the reach at 100 days, and runs collect
// the given number of times (history_days 365, chunks of 100 days): the
// first run reads the chunk 100 to 200 days back (B and A), the second 200
// to 300 (Z), the third nothing new. It returns the history's path.
func backfillRuns(t *testing.T, g *gitHub, runs int) string {
	t.Helper()
	path := historyPath(t)
	storeAges(t, path, []int{5})
	reach := history.Reach{"acme/app": ago(100)}
	if err := history.SaveReach(filepath.Join(filepath.Dir(path), "reach.csv"), reach); err != nil {
		t.Fatal(err)
	}
	cfg := shop(production)
	cfg.HistoryDays, cfg.HistoryChunkDays = 365, 100
	for range runs {
		if r := g.collect(t, cfg, path, 10); r.err != nil {
			t.Fatalf("want a run, got %v (stderr %q)", r.err, r.stderr)
		}
	}
	return path
}

// The commits of B (compared with A), of P (the oldest stored success
// before the first run, compared with B once B is read) and of A (compared
// with Z).
func commitB() history.Commit { return commit(1150, shaE, ago(160), ago(150)) }
func commitP() history.Commit { return commit(1005, shaF, ago(100), ago(5)) }
func commitA() history.Commit { return commit(1180, shaG, ago(200), ago(180)) }

// TestAnOlderChunkGetsCommitsExceptItsOldest: the chunk holding A and B is
// stored after P. B gets the commits of compare(A, B). A, whose previous is
// not read yet, gets none. P, until then the oldest of its stream and
// waiting, gets compare(B, P).
func TestAnOlderChunkGetsCommitsExceptItsOldest(t *testing.T) {
	path := backfillRuns(t, backfillGitHub(t), 1)
	wantCommits(t, path, commitB(), commitP())
}

// TestTheNextChunkGivesTheWaitingDeploymentItsCommits: Z, A's previous,
// arrives with the next chunk, and A gets compare(Z, A).
func TestTheNextChunkGivesTheWaitingDeploymentItsCommits(t *testing.T) {
	path := backfillRuns(t, backfillGitHub(t), 2)
	wantCommits(t, path, commitB(), commitP(), commitA())
}

// TestNoCommitIsStoredTwiceOrComparedAgain: a run that reads nothing new
// stores no commit again, and GitHub is asked for no comparison twice.
func TestNoCommitIsStoredTwiceOrComparedAgain(t *testing.T) {
	g := backfillGitHub(t)
	path := backfillRuns(t, g, 3)
	wantCommits(t, path, commitB(), commitP(), commitA())
	for _, c := range [][2]string{{shaB, shaC}, {shaC, shaD}, {shaA, shaB}} {
		if got := g.seen(comparePath(c[0], c[1])); len(got) != 1 {
			t.Errorf("want one comparison of %.1s and %.1s, got %v", c[0], c[1], got)
		}
	}
}
