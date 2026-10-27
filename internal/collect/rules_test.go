package collect

import (
	"errors"
	"fmt"
	"io/fs"
	"slices"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// Several deployment rules for one repository (forsgren#498, step 2): each
// rule's deployments are read into their own stream, compared within it, and
// the repository's reach does not pass what any rule has read.

// ruled is acme/app with the given rules, in order; its Deployment is the
// first rule's, as Load sets it.
func ruled(rules ...config.Deployment) config.Repository {
	r := config.Repository{Name: "acme/app", Deployment: rules[0]}
	for i, d := range rules {
		r.Rules = append(r.Rules, config.Rule{Deployment: d, Label: "Rule " + string(rune('A'+i))})
	}
	return r
}

var (
	envProduction = config.Deployment{Kind: config.Environment, Name: "production"}
	envStaging    = config.Deployment{Kind: config.Environment, Name: "staging"}
	releases      = config.Deployment{Kind: config.Release}
)

// sortedByID is the records of the history at path, by ID.
func sortedByID(t *testing.T, path string) []history.Record {
	t.Helper()
	records, err := history.Load(path)
	if err != nil {
		t.Fatal(err)
	}
	slices.SortFunc(records, func(a, b history.Record) int { return int(a.ID - b.ID) })
	return records
}

// TestSeveralRulesAreReadIntoTheirOwnStreams: an environment rule and a
// release rule each store their new deployment, and each is compared with the
// previous success of its own stream: the environment's with the earlier
// environment deployment, the release with the earlier release, never one
// with the other's.
func TestSeveralRulesAreReadIntoTheirOwnStreams(t *testing.T) {
	path := historyHolding(t,
		record(history.KindEnvironment, "production", 1001, shaA, at(21, 10, 0), history.StateSuccess, "deploy"),
		record(history.KindRelease, "", 9001, shaA, at(10, 9, 0), history.StateSuccess, "v1.0.0"))
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list(deployment(1002, shaB, "deploy", "2026-09-22T10:00:00Z"),
		deployment(1001, shaA, "deploy", "2026-09-21T10:00:00Z"))
	g.succeeded("1002")
	g.bodies["/repos/acme/app/releases"] = list(release(9002, "v1.1.0", false, false, "2026-09-22T09:00:00Z"),
		release(9001, "v1.0.0", false, false, "2026-09-10T09:00:00Z"))
	g.bodies["/repos/acme/app/commits/tags/v1.1.0"] = shaC
	g.bodies[comparePath(shaA, shaB)] = ahead(authored{shaB, at(22, 8, 0)})
	g.bodies[comparePath(shaA, shaC)] = ahead(authored{shaC, at(22, 7, 0)})
	wantStdout(t, g.collect(t, shop(ruled(envProduction, releases)), path, github.DefaultMaxPages),
		"acme/app: 2 new, 0 skipped (not final), 2 commits\n")
	got := sortedByID(t, path)
	want := []history.Record{
		record(history.KindEnvironment, "production", 1001, shaA, at(21, 10, 0), history.StateSuccess, "deploy"),
		record(history.KindEnvironment, "production", 1002, shaB, at(22, 10, 0), history.StateSuccess, "deploy"),
		record(history.KindRelease, "", 9001, shaA, at(10, 9, 0), history.StateSuccess, "v1.0.0"),
		record(history.KindRelease, "", 9002, shaC, at(22, 9, 0), history.StateSuccess, "v1.1.0"),
	}
	if !slices.Equal(got, want) {
		t.Errorf("want the records\n%v\ngot\n%v", want, got)
	}
	if compares := g.seen("/repos/acme/app/compare/"); len(compares) != 2 {
		t.Errorf("want the two comparisons of the two streams, got %v", compares)
	}
}

// TestTwoEnvironmentRulesHideNothingFromEachOther: staging has a deployment
// stored from 29 September and the repository's history is read back to
// history_days, so staging reads only what is new; production has none stored,
// so its own window reaches back and takes the 10 September deployment that
// GitHub lists, which staging's window does not reach.
func TestTwoEnvironmentRulesHideNothingFromEachOther(t *testing.T) {
	path := historyHolding(t,
		record(history.KindEnvironment, "staging", 1001, shaA, at(29, 10, 0), history.StateSuccess, "deploy"))
	fullyRead(t, path)
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list(deployment(1002, shaB, "deploy", "2026-09-10T10:00:00Z"))
	g.succeeded("1002")
	g.collect(t, shop(ruled(envStaging, envProduction)), path, github.DefaultMaxPages)
	var names []string
	for _, r := range sortedByID(t, path) {
		names = append(names, fmt.Sprint(r.ID, " ", r.Name))
	}
	if want := []string{"1001 staging", "1002 production"}; !slices.Equal(names, want) {
		t.Errorf("want the 10 September deployment stored for production, got %v", names)
	}
}

// TestARuleAddedToAReadRepositoryIsReadFromItsFirstChunk: acme/app has its
// environment deployments stored and a reach 200 days back; the release rule
// is new, so it reads its first chunk (the recent 100 days, the 5 day old
// release), and the reach does not pass what it has read: it moves to 100 days
// back, though the environment rule read the chunk behind its own.
func TestARuleAddedToAReadRepositoryIsReadFromItsFirstChunk(t *testing.T) {
	tc := chunkCase{stored: []int{5}, reachAge: 200}
	g := chunkGitHub(t, tc)
	g.bodies["/repos/acme/app/releases"] = list(
		release(9005, "v1.5.0", false, false, ago(5).Format(time.RFC3339)),
		release(9150, "v1.0.0", false, false, ago(150).Format(time.RFC3339)))
	g.bodies["/repos/acme/app/commits/tags/v1.5.0"] = shaB
	path := historyPath(t)
	seedChunk(t, path, reachFileOf(path), tc)
	cfg := shopWithChunks()
	cfg.Projects[0].Repositories = []config.Repository{ruled(envProduction, releases)}
	if r := g.collect(t, cfg, path, github.DefaultMaxPages); r.err != nil {
		t.Fatalf("want no error, got %v (stderr %q)", r.err, r.stderr)
	}
	reach, err := history.LoadReach(reachFileOf(path))
	if want := ago(100); err != nil || !reach["acme/app"].Equal(want) {
		t.Errorf("want the reach of acme/app at %s, got %v, %v", want, reach, err)
	}
	if tags := releaseTags(t, path); !slices.Equal(tags, []string{"v1.5.0"}) {
		t.Errorf("want only the recent release stored, got %v", tags)
	}
}

// releaseTags are the tags of the releases in the history at path.
func releaseTags(t *testing.T, path string) []string {
	t.Helper()
	var tags []string
	for _, r := range sortedByID(t, path) {
		if r.Kind == history.KindRelease {
			tags = append(tags, r.Task)
		}
	}
	return tags
}

// TestADeploymentOfAnotherRuleIsAnotherSource: the history's source of a
// repository is its kind and its name, so two environments are two sources.
func TestADeploymentOfAnotherRuleIsAnotherSource(t *testing.T) {
	a := sourceOf(record(history.KindEnvironment, "staging", 1, shaA, at(1, 0, 0), history.StateSuccess, ""))
	b := sourceOf(record(history.KindEnvironment, "production", 2, shaA, at(1, 0, 0), history.StateSuccess, ""))
	if a == b {
		t.Errorf("want one source for each environment name, got %v and %v", a, b)
	}
}

// TestARuleCutShortByTheBudgetEndsTheReading: the first rule's read is cut in
// the middle of a day, as it is for a repository of one rule (it keeps the
// whole days), the release rule behind it is not read at all, and the reach
// does not pass what that unread rule would have read: it stays.
func TestARuleCutShortByTheBudgetEndsTheReading(t *testing.T) {
	g, path := busyGitHub(t)
	g.allow = 11
	cfg := shopWithChunks()
	cfg.Projects[0].Repositories = []config.Repository{ruled(envProduction, releases)}
	r := g.collect(t, cfg, path, github.DefaultMaxPages)
	wantCutShort(t, r)
	wantStoredIDs(t, path, storedOne, 2011, 2012, 2021, 2022)
	wantReachAtDay(t, path, 100)
	if got := g.seen("/repos/acme/app/releases"); len(got) != 0 {
		t.Errorf("want the release rule not read, got %v", got)
	}
}

// TestTheReachOfSeveralRulesIsTheLatestTheyGive: the table of reachAfter. A
// rule that leaves the reach, and a rule not read, are the reach it is at; an
// unknown reach stays unknown; the result is zero when it is the reach it is.
func TestTheReachOfSeveralRulesIsTheLatestTheyGive(t *testing.T) {
	d := func(days int) time.Time { return ago(days) }
	h := held{reach: history.Reach{"acme/app": d(100)}}
	unknown := held{reach: history.Reach{}}
	for name, tc := range map[string]struct {
		h       held
		reaches []time.Time
		unread  int
		want    time.Time
	}{
		"all deeper":       {h, []time.Time{d(200), d(300)}, 0, d(200)},
		"a shallower one":  {h, []time.Time{d(200), d(50)}, 0, d(50)},
		"one leaves it":    {h, []time.Time{d(200), {}}, 0, time.Time{}},
		"one not read":     {h, []time.Time{d(200)}, 1, time.Time{}},
		"unknown reach":    {unknown, []time.Time{d(200), {}}, 0, time.Time{}},
		"all first chunks": {unknown, []time.Time{d(100), d(50)}, 0, d(50)},
	} {
		if got := tc.h.reachAfter("Acme/App", tc.reaches, tc.unread); !got.Equal(tc.want) {
			t.Errorf("%s: want %v, got %v", name, tc.want, got)
		}
	}
}

// TestARuleThatFailsFailsTheRepositoryAndStoresNothingOfIt: the release list
// is refused, so the repository fails as one of a single rule would, and the
// environment deployment that was read before it is not stored either.
func TestARuleThatFailsFailsTheRepositoryAndStoresNothingOfIt(t *testing.T) {
	path := historyPath(t)
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list(deployment(1002, shaB, "deploy", "2026-09-22T10:00:00Z"))
	g.succeeded("1002")
	g.bodies["/repos/acme/app/releases"] = `{"message":"boom"}`
	g.status["/repos/acme/app/releases"] = 500
	r := g.collect(t, shop(ruled(envProduction, releases)), path, github.DefaultMaxPages)
	if !errors.Is(r.err, ErrFailed) {
		t.Errorf("want ErrFailed, got %v", r.err)
	}
	if _, err := history.Load(path); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("want nothing stored, got %v", err)
	}
}

// TestTheOldestSeenOfTwoRulesIsTheEarlierOneRead: a zero time is none read.
func TestTheOldestSeenOfTwoRulesIsTheEarlierOneRead(t *testing.T) {
	a, b := ago(5), ago(9)
	for name, tc := range map[string]struct{ x, y, want time.Time }{
		"none":         {time.Time{}, time.Time{}, time.Time{}},
		"only the one": {a, time.Time{}, a},
		"only other":   {time.Time{}, b, b},
		"both":         {a, b, b},
	} {
		if got := earliestSeen(tc.x, tc.y); !got.Equal(tc.want) {
			t.Errorf("%s: want %v, got %v", name, tc.want, got)
		}
	}
}
