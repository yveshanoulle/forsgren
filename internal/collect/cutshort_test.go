package collect

import (
	"cmp"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// A busy chunk (forsgren#64, step 2, decision #239): acme/app has one stored
// success, 1005, five days old, and reach.csv says it was read back to 100
// days ago. Behind that lie four days of two successes each, the first of a
// day created at 14:00 (ID 2000+10*day+1) and the second at 09:00 (+2), day 1
// being the newest. Every success is compared with the one before it, and a
// comparison has one commit, the head's.

const (
	busyDays  = 4
	storedOne = 1005
)

// busySha is the commit of deployment id.
func busySha(id int64) string { return fmt.Sprintf("%040d", id) }

// busyCreated is when deployment id was created: 1005 five days ago, else
// that day's afternoon (kind 1) or morning (kind 2).
func busyCreated(id int64) time.Time {
	if id == storedOne {
		return ago(5)
	}
	hour := map[int64]time.Duration{1: 14, 2: 9}[id%10]
	return ago(100 + int(id-2000)/10).Add(hour * time.Hour)
}

// busyIDs are the IDs of the busy chunk and 1005 behind it, newest first.
func busyIDs() []int64 {
	ids := []int64{storedOne}
	for day := 1; day <= busyDays; day++ {
		ids = append(ids, int64(2000+10*day+1), int64(2000+10*day+2))
	}
	return ids
}

// busyGitHub is a fake GitHub that lists the busy chunk, gives each success
// its status and answers every comparison of one success with the one before
// it, and the path of the history, which already holds 1005 and a reach.csv
// at 100 days.
func busyGitHub(t *testing.T) (*gitHub, string) {
	t.Helper()
	g := newGitHub(t)
	ids := busyIDs()
	var listed []string
	for _, id := range ids {
		created := busyCreated(id).Format(time.RFC3339)
		listed = append(listed, deployment(id, busySha(id), "deploy", created))
		g.bodies[statusesPath(fmt.Sprint(id))] = list(status(id, "success", created))
	}
	g.bodies[deploymentsPath] = list(listed...)
	for i := 1; i < len(ids); i++ {
		head, base := ids[i-1], ids[i]
		g.bodies[comparePath(busySha(base), busySha(head))] = ahead(authored{busySha(head), busyCreated(head)})
	}
	path := historyPath(t)
	seedChunk(t, path, reachFileOf(path), chunkCase{stored: nil, reachAge: 100})
	held := record(history.KindEnvironment, "production", storedOne, busySha(storedOne), ago(5),
		history.StateSuccess, "deploy")
	if _, err := history.Append(path, []history.Record{held}); err != nil {
		t.Fatal(err)
	}
	return g, path
}

// wantStoredIDs fails unless the history at path holds exactly these
// deployments.
func wantStoredIDs(t *testing.T, path string, want ...int64) {
	t.Helper()
	records, err := history.Load(path)
	if err != nil {
		t.Fatal(err)
	}
	var got []int64
	for _, r := range records {
		got = append(got, r.ID)
	}
	slices.Sort(got)
	slices.Sort(want)
	if !slices.Equal(got, want) {
		t.Errorf("want the deployments %v stored, got %v", want, got)
	}
}

// wantCommitsOf fails unless the commits file holds the commits of exactly
// these deployments, one each, none twice.
func wantCommitsOf(t *testing.T, path string, want ...int64) {
	t.Helper()
	commits, err := history.LoadCommits(commitsPath(path))
	if err != nil {
		t.Fatal(err)
	}
	var got []int64
	for _, c := range commits {
		got = append(got, c.DeploymentID)
	}
	slices.Sort(got)
	slices.Sort(want)
	if !slices.Equal(got, want) {
		t.Errorf("want the commits of the deployments %v, got those of %v", want, got)
	}
}

// wantReachAtDay fails unless acme/app's reach is the start of the day that
// is days days before now.
func wantReachAtDay(t *testing.T, path string, days int) {
	t.Helper()
	reach, err := history.LoadReach(reachFileOf(path))
	if want := ago(days); err != nil || !reach["acme/app"].Equal(want) {
		t.Errorf("want the reach of acme/app at %s, got %v, %v", want, reach, err)
	}
}

// wantCutShort fails unless the run exits 0 and names acme/app as cut short.
func wantCutShort(t *testing.T, r result) {
	t.Helper()
	if r.err != nil || !strings.Contains(r.stderr, "collect: cut short: acme/app: ") {
		t.Errorf("want acme/app cut short and no error, got %v (stderr %q)", r.err, r.stderr)
	}
}

// TestACutInTheMiddleOfADayKeepsOnlyWholeDays: 11 requests are allowed, and
// the statuses of day 3's second success are not read, the reserve for the
// comparisons being used up. Day 3 is half read, so none of it is stored, not
// the success read: days 1 and 2 are, with their commits, and the reach moves
// to the start of day 2, the oldest whole day. A half-read day kept would
// leave day 3's other success unread, behind a reach that says it was read.
func TestACutInTheMiddleOfADayKeepsOnlyWholeDays(t *testing.T) {
	g, path := busyGitHub(t)
	g.allow = 11
	r := g.collect(t, shopWithChunks(), path, github.DefaultMaxPages)
	wantCutShort(t, r)
	wantStoredIDs(t, path, storedOne, 2011, 2012, 2021, 2022)
	wantCommitsOf(t, path, storedOne, 2011, 2012, 2021)
	wantReachAtDay(t, path, 102)
	wantStdoutIs(t, r, "acme/app: 4 new, 0 skipped (not final), 4 commits\n")
}

// wantStdoutIs fails unless stdout is want, whatever the run returned.
func wantStdoutIs(t *testing.T, r result, want string) {
	t.Helper()
	if r.stdout != want {
		t.Errorf("want stdout %q, got %q", want, r.stdout)
	}
}

// TestACutInTheComparisonsKeepsOnlyComparedDays: all eight statuses are read,
// but only seven of the eight comparisons are allowed. The eighth belongs to
// day 4's first success, so day 4 is dropped whole and the reach moves to the
// start of day 3; the commits of the days kept are all there, the last of
// them compared with the success of the dropped day, which is right.
func TestACutInTheComparisonsKeepsOnlyComparedDays(t *testing.T) {
	g, path := busyGitHub(t)
	g.allow = 16
	r := g.collect(t, shopWithChunks(), path, github.DefaultMaxPages)
	wantCutShort(t, r)
	wantStoredIDs(t, path, storedOne, 2011, 2012, 2021, 2022, 2031, 2032)
	wantCommitsOf(t, path, storedOne, 2011, 2012, 2021, 2022, 2031, 2032)
	wantReachAtDay(t, path, 103)
}

// TestAChunkBiggerThanOneRunsBudgetProgressesAcrossRuns: with 11 requests a
// run, the busy chunk needs several runs, each storing whole days and moving
// the reach back, and ends where one run with the whole budget ends, the
// same deployments, the same commits, none twice, the same reach.
func TestAChunkBiggerThanOneRunsBudgetProgressesAcrossRuns(t *testing.T) {
	whole, wholePath := busyGitHub(t)
	if r := whole.collect(t, shopWithChunks(), wholePath, github.DefaultMaxPages); r.err != nil {
		t.Fatalf("want the uncut run to pass, got %v", r.err)
	}
	g, path := busyGitHub(t)
	g.allow = 11
	last := 0
	for run := 1; run <= 5; run++ {
		r := g.collect(t, shopWithChunks(), path, github.DefaultMaxPages)
		if r.err != nil {
			t.Fatalf("run %d: %v", run, r.err)
		}
		stored := len(recordsOf(t, path))
		if len(recordsOf(t, path)) == len(recordsOf(t, wholePath)) {
			wantSameEnd(t, wholePath, path)
			return
		}
		if stored <= last {
			t.Fatalf("run %d: want progress, got %d deployments stored after %d", run, stored, last)
		}
		last = stored
	}
	t.Error("want the chunk read in 5 runs, still cut short")
}

// recordsOf are the deployments of the history at path.
func recordsOf(t *testing.T, path string) []history.Record {
	t.Helper()
	records, err := history.Load(path)
	if err != nil {
		t.Fatal(err)
	}
	return records
}

// wantSameEnd fails unless the history and the commits at path are those of
// the run at whole, line for line (a success compared twice leaves no second
// line), and the reach is no later than the one run's.
func wantSameEnd(t *testing.T, whole, path string) {
	t.Helper()
	byID := func(a, b history.Record) int { return int(a.ID - b.ID) }
	got, want := recordsOf(t, path), recordsOf(t, whole)
	slices.SortFunc(got, byID)
	slices.SortFunc(want, byID)
	if !slices.Equal(got, want) {
		t.Errorf("want the deployments\n%v\ngot\n%v", want, got)
	}
	gotCommits, wantCommits := sortedCommits(t, path), sortedCommits(t, whole)
	if !slices.EqualFunc(gotCommits, wantCommits, sameCommit) {
		t.Errorf("want the commits\n%v\ngot\n%v", wantCommits, gotCommits)
	}
	reachWhole, _ := history.LoadReach(reachFileOf(whole))
	reachGot, _ := history.LoadReach(reachFileOf(path))
	if reachGot["acme/app"].After(reachWhole["acme/app"]) {
		t.Errorf("want the reach no later than %v, got %v", reachWhole, reachGot)
	}
}

// sortedCommits are the commits file next to the history at path, ordered by
// deployment and SHA, every line kept.
func sortedCommits(t *testing.T, path string) []history.Commit {
	t.Helper()
	commits, err := history.LoadCommits(commitsPath(path))
	if err != nil {
		t.Fatal(err)
	}
	slices.SortFunc(commits, func(a, b history.Commit) int {
		return cmp.Or(int(a.DeploymentID-b.DeploymentID), strings.Compare(a.SHA, b.SHA))
	})
	return commits
}

// TestAComparisonRepeatedAcrossRunsLeavesTheCommitsOfAnUncutRun: a cut in the
// comparisons leaves day 3's last success compared with the success of day 4,
// which is dropped; the next run reads day 4 and compares the oldest stored
// success again, with the same result, which the commits file skips.
func TestAComparisonRepeatedAcrossRunsLeavesTheCommitsOfAnUncutRun(t *testing.T) {
	whole, wholePath := busyGitHub(t)
	whole.collect(t, shopWithChunks(), wholePath, github.DefaultMaxPages)
	g, path := busyGitHub(t)
	g.allow = 16
	g.collect(t, shopWithChunks(), path, github.DefaultMaxPages)
	g.allow = 0
	g.collect(t, shopWithChunks(), path, github.DefaultMaxPages)
	wantSameEnd(t, wholePath, path)
}

// TestACutInTheIssueReadKeepsTheDeployments: the deployment is read and
// stored, but the budget goes in the read of the issues. That read is stored
// whole or not at all, with the marks that say it was read, so none of them
// is; the next run reads the issues again.
func TestACutInTheIssueReadKeepsTheDeployments(t *testing.T) {
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list(deployment(storedOne, busySha(storedOne), "deploy", ago(5).Format(time.RFC3339)))
	g.bodies[statusesPath("1005")] = list(status(1, "success", ago(5).Format(time.RFC3339)))
	path := historyPath(t)
	g.allow = 3
	r := g.collect(t, shopWithChunks(), path, github.DefaultMaxPages)
	wantCutShort(t, r)
	wantStoredIDs(t, path, storedOne)
	for _, name := range []string{FailuresReadFile, "issues_full.csv", "issues.csv", "failures.csv"} {
		if rows := rowsOf(t, path, name); rows != 0 {
			t.Errorf("want nothing of the issue read in %s, got %d lines", name, rows)
		}
	}
}

// rowsOf is how many data lines the file name next to the history at path
// has after its two header lines, 0 when there is none.
func rowsOf(t *testing.T, path, name string) int {
	t.Helper()
	data, err := os.ReadFile(filepath.Clean(filepath.Join(filepath.Dir(path), name)))
	if errors.Is(err, fs.ErrNotExist) {
		return 0
	}
	if err != nil {
		t.Fatal(err)
	}
	return max(0, strings.Count(string(data), "\n")-2)
}

// boundaryGitHub is a fake GitHub with acme/app's stored success 1005, the
// reach at 100 days, and two successes either side of a UTC midnight: 3001 at
// 00:00:00 on the day 101 days ago and 3002 at 23:59:59 the day before. It
// returns the path of the history.
func boundaryGitHub(t *testing.T) (*gitHub, string) {
	t.Helper()
	g := newGitHub(t)
	times := map[int64]time.Time{storedOne: ago(5), 3001: ago(101), 3002: ago(101).Add(-time.Second)}
	var listed []string
	for _, id := range []int64{storedOne, 3001, 3002} {
		created := times[id].Format(time.RFC3339)
		listed = append(listed, deployment(id, busySha(id), "deploy", created))
		g.bodies[statusesPath(fmt.Sprint(id))] = list(status(id, "success", created))
	}
	g.bodies[deploymentsPath] = list(listed...)
	g.bodies[comparePath(busySha(3001), busySha(storedOne))] = ahead(authored{busySha(storedOne), ago(5)})
	g.bodies[comparePath(busySha(3002), busySha(3001))] = ahead(authored{busySha(3001), ago(101)})
	path := historyPath(t)
	seedChunk(t, path, reachFileOf(path), chunkCase{reachAge: 100})
	held := record(history.KindEnvironment, "production", storedOne, busySha(storedOne), ago(5),
		history.StateSuccess, "deploy")
	if _, err := history.Append(path, []history.Record{held}); err != nil {
		t.Fatal(err)
	}
	return g, path
}

// TestACutAtAMidnightNeverMovesTheReachPastUnreadData: 3001 is created at
// 00:00:00 and 3002 at 23:59:59 the day before. Cut before 3001's statuses,
// nothing is kept and the reach stays; cut between them (3002 not read) the
// day of 3001 is whole, so 3001 is kept and the reach is that midnight, and
// not a second later; cut in the comparisons of 3001, nothing is kept and the
// reach stays.
func TestACutAtAMidnightNeverMovesTheReachPastUnreadData(t *testing.T) {
	cases := []struct {
		name      string
		allow     int
		stored    []int64
		reachDays int
	}{
		{"before the later one", 1, []int64{storedOne}, 100},
		{"between them", 3, []int64{storedOne, 3001}, 101},
		{"in the comparison of the later one", 4, []int64{storedOne}, 100},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			g, path := boundaryGitHub(t)
			g.allow = c.allow
			wantCutShort(t, g.collect(t, shopWithChunks(), path, github.DefaultMaxPages))
			wantStoredIDs(t, path, c.stored...)
			wantReachAtDay(t, path, c.reachDays)
		})
	}
}

// TestARepositoryAtTheMarginOnEveryRunStaysPutAndIsNamed: a repository that
// is at the budget's margin from its first request on, run after run, stores
// nothing, moves no read mark, and each run names it as cut short on stderr,
// so it never looks like progress.
func TestARepositoryAtTheMarginOnEveryRunStaysPutAndIsNamed(t *testing.T) {
	g, path := boundaryGitHub(t)
	g.allow = 1
	for run := 1; run <= 3; run++ {
		r := g.collect(t, shopWithChunks(), path, github.DefaultMaxPages)
		wantCutShort(t, r)
		wantStoredIDs(t, path, storedOne)
		wantReachAtDay(t, path, 100)
		wantStdoutIs(t, r, "")
	}
}

// recentGitHub is boundaryGitHub with a newer success, 4001, a day old, that
// the recent read finds and compares with 1005.
func recentGitHub(t *testing.T) (*gitHub, string) {
	t.Helper()
	g, path := boundaryGitHub(t)
	created := ago(1).Format(time.RFC3339)
	newest := deployment(4001, busySha(4001), "deploy", created)
	g.bodies[deploymentsPath] = "[" + newest + "," + strings.TrimPrefix(g.bodies[deploymentsPath], "[")
	g.bodies[statusesPath("4001")] = list(status(1, "success", created))
	g.bodies[comparePath(busySha(storedOne), busySha(4001))] = ahead(authored{busySha(4001), ago(1)})
	return g, path
}

// TestACutInTheComparisonOfTheNewestDayKeepsNothing: the newest day's
// success is the one whose comparison the budget stops, so no day of the
// recent read is whole, nothing is stored, and the read mark stays.
func TestACutInTheComparisonOfTheNewestDayKeepsNothing(t *testing.T) {
	g, path := recentGitHub(t)
	g.allow = 1
	wantCutShort(t, g.collect(t, shopWithChunks(), path, github.DefaultMaxPages))
	wantStoredIDs(t, path, storedOne)
	wantReachAtDay(t, path, 100)
}

// TestACutInTheOlderChunkKeepsTheRecentReadWhole: the recent read is whole and
// compared; the older chunk is cut at its first success, so no day of it is
// kept and the reach stays.
func TestACutInTheOlderChunkKeepsTheRecentReadWhole(t *testing.T) {
	g, path := recentGitHub(t)
	g.allow = 3
	wantCutShort(t, g.collect(t, shopWithChunks(), path, github.DefaultMaxPages))
	wantStoredIDs(t, path, storedOne, 4001)
	wantCommitsOf(t, path, 4001)
	wantReachAtDay(t, path, 100)
}

// TestACutReleaseStoresNothingAndMovesNoMark: a release rule whose tag lookup
// the budget refuses keeps no release, so it writes no history and no reach.
func TestACutReleaseStoresNothingAndMovesNoMark(t *testing.T) {
	g := newGitHub(t)
	g.bodies["/repos/acme/app/releases"] = list(release(1, "v1.0.0", false, false, "2026-09-20T10:00:00Z"))
	g.left["/repos/acme/app/releases"] = 80
	path := historyPath(t)
	wantCutShort(t, g.collect(t, shop(repository("acme/app", config.Release, "")), path, github.DefaultMaxPages))
	if _, err := os.Stat(path); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("want no history written, got %v", err)
	}
	if _, err := os.Stat(reachFileOf(path)); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("want no reach written, got %v", err)
	}
}

// TestAStoreThatFailsAfterACutFailsTheRepository: the days kept cannot be
// written, so the repository fails, naming the file, and moves no mark.
func TestAStoreThatFailsAfterACutFailsTheRepository(t *testing.T) {
	g, path := boundaryGitHub(t)
	if err := os.Chmod(path, 0o400); err != nil {
		t.Fatal(err)
	}
	g.allow = 3
	r := g.collect(t, shopWithChunks(), path, github.DefaultMaxPages)
	if !errors.Is(r.err, ErrFailed) || !strings.Contains(r.stderr, "deployments.csv") {
		t.Errorf("want a failed repository naming deployments.csv, got %v (stderr %q)", r.err, r.stderr)
	}
	wantReachAtDay(t, path, 100)
}

// Lookback fixtures (forsgren#64, step 2b, decision #239): acme/app has the
// stored success 1005 at N0, 20 days ago, and reach.csv at 100 days. GitHub
// lists the newer 5001 (at the time a case gives, in a day of its own) and
// then 5002, six hours after N0, in the day of N0. The comparison of 5001
// with 1005 holds the commits of both. With 2 requests allowed the budget
// stops at the statuses of 5002, so only 5001's day was read whole. The next
// run's window starts 7 days before the newest deployment stored, so storing
// 5001 is safe only while that is no later than N0: 5002 is newer than N0 and
// may lie anywhere between.

const (
	lookbackNewest = 5001
	lookbackOlder  = 5002
)

// lookbackGitHub is the fake of those fixtures with 5001 created at newest,
// and the path of the history.
func lookbackGitHub(t *testing.T, newest time.Time) (*gitHub, string) {
	t.Helper()
	g := newGitHub(t)
	older := ago(20).Add(6 * time.Hour)
	times := map[int64]time.Time{lookbackNewest: newest, lookbackOlder: older}
	var listed []string
	for _, id := range []int64{lookbackNewest, lookbackOlder} {
		created := times[id].Format(time.RFC3339)
		listed = append(listed, deployment(id, busySha(id), "deploy", created))
		g.bodies[statusesPath(fmt.Sprint(id))] = list(status(1, "success", created))
	}
	g.bodies[deploymentsPath] = list(listed...)
	g.bodies[comparePath(busySha(storedOne), busySha(lookbackNewest))] = ahead(
		authored{busySha(lookbackOlder), older}, authored{busySha(lookbackNewest), newest})
	g.bodies[comparePath(busySha(storedOne), busySha(lookbackOlder))] = ahead(authored{busySha(lookbackOlder), older})
	path := historyPath(t)
	seedChunk(t, path, reachFileOf(path), chunkCase{reachAge: 100})
	held := record(history.KindEnvironment, "production", storedOne, busySha(storedOne), ago(20),
		history.StateSuccess, "deploy")
	if _, err := history.Append(path, []history.Record{held}); err != nil {
		t.Fatal(err)
	}
	return g, path
}

// TestACutRecentReadKeepsItsWholeDaysWhileTheNextWindowReachesWhatWasNotRead:
// 5001 is created exactly 7 days after N0 (inside: the next window starts at
// N0) and it is stored, with its commits; one second later (outside) nothing
// is stored; and the read mark stays in both. The next run, with the budget,
// stores 5002 in the first case, which lies between two stored successes and
// so gets no commits and a warning, none counted twice.
func TestACutRecentReadKeepsItsWholeDaysWhileTheNextWindowReachesWhatWasNotRead(t *testing.T) {
	cases := []struct {
		name   string
		offset time.Duration
		stored []int64
	}{
		{"exactly the lookback after the oldest not read", Lookback, []int64{storedOne, lookbackNewest}},
		{"a second beyond it", Lookback + time.Second, []int64{storedOne}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			g, path := lookbackGitHub(t, ago(20).Add(c.offset))
			g.allow = 2
			wantCutShort(t, g.collect(t, shopWithChunks(), path, github.DefaultMaxPages))
			wantStoredIDs(t, path, c.stored...)
			wantReachAtDay(t, path, 100)
		})
	}
}

// TestADayKeptBeyondTheNextWindowWouldLoseWhatWasNotRead (the mutation proof
// of the rule above): 5001 is 7.5 days after N0, so the next window starts
// after 5002, which was not read. Nothing is stored, and the next run, with
// the budget, stores both; a run that kept 5001 would never see 5002.
func TestADayKeptBeyondTheNextWindowWouldLoseWhatWasNotRead(t *testing.T) {
	g, path := lookbackGitHub(t, ago(20).Add(Lookback+12*time.Hour))
	g.allow = 2
	wantCutShort(t, g.collect(t, shopWithChunks(), path, github.DefaultMaxPages))
	wantStoredIDs(t, path, storedOne)
	g.allow = 0
	if r := g.collect(t, shopWithChunks(), path, github.DefaultMaxPages); r.err != nil {
		t.Fatal(r.err)
	}
	wantStoredIDs(t, path, storedOne, lookbackNewest, lookbackOlder)
}

// TestWhatTheNextRunReadsAfterAKeptDayIsNotCountedTwice: after the inside
// case the next run stores 5002, between 1005 and 5001, with the warning and
// no commits of its own, and every commit is in the file once.
func TestWhatTheNextRunReadsAfterAKeptDayIsNotCountedTwice(t *testing.T) {
	g, path := lookbackGitHub(t, ago(20).Add(Lookback))
	g.allow = 2
	g.collect(t, shopWithChunks(), path, github.DefaultMaxPages)
	g.allow = 0
	r := g.collect(t, shopWithChunks(), path, github.DefaultMaxPages)
	wantStoredIDs(t, path, storedOne, lookbackNewest, lookbackOlder)
	wantCommitsOf(t, path, lookbackNewest, lookbackNewest)
	if !strings.Contains(r.stderr, "no commit counts twice") {
		t.Errorf("want the warning for the deployment between two stored ones, got %q", r.stderr)
	}
}
