package collect

import (
	"reflect"
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/github"
)

// twoPushes gives g the activity list of acme/app: two pushes to main, the
// newer one (C to D) compared first.
func twoPushes(g *gitHub) {
	g.bodies[activityPath] = list(
		activityOf("push", pushTime2, shaC, shaD),
		activityOf("push", pushTime1, shaB, shaC))
	g.bodies[comparePath(shaC, shaD)] = chain(shaC, shaD)
	g.bodies[comparePath(shaB, shaC)] = chain(shaB, shaC)
}

// TestTheLegacyBackfillRunsBeforeThePushReadSoTheFirstPushReadCannotStarveIt
// (forsgren#416): the first push read costs one compare per push, so a budget
// that covers the backfill's comparison but not both pushes was spent in the
// push read. The backfill goes first: the legacy commits are filled, the
// newer push is stored, the older one is cut short and read again by the next
// run, and the backfill is marked, since a pushes cut is neither a failure
// nor a cut of the backfill.
func TestTheLegacyBackfillRunsBeforeThePushReadSoTheFirstPushReadCannotStarveIt(t *testing.T) {
	g, path := withLegacyCommits(t)
	twoPushes(g)
	g.left[comparePath(shaC, shaD)] = 249
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if r.err != nil {
		t.Fatalf("want no error, got %v (stderr %q)", r.err, r.stderr)
	}
	filled := commit(1002, shaC, at(21, 9, 0), at(22, 10, 0))
	filled.Author = "ada-dev"
	noAccount := commit(1002, shaB, at(22, 8, 0), at(22, 10, 0))
	untouched := commit(1003, shaD, at(23, 8, 0), at(23, 10, 0))
	untouched.Author = "bob-dev"
	wantCommits(t, path, landed(filled, at(21, 9, 30), shaA), landed(noAccount, at(22, 8, 30), shaC),
		landed(untouched, at(23, 8, 30), shaB))
	dataOf(path).want(t, PushesFile, pushesHeader+linePush(pushTime2, shaC, shaD, "push", "false", "1"))
	wantBackfillMark(t, path)
	if want := (Report{PushesCut: []string{"acme/app"}, Reset: g.resetAt.UTC()}); !reflect.DeepEqual(g.report, want) {
		t.Errorf("want the report %+v, got %+v", want, g.report)
	}
	if !strings.Contains(r.stderr, "the pushes were cut short") || strings.Contains(r.stderr, "failed") {
		t.Errorf("want the pushes cut short and nothing failed, got %q", r.stderr)
	}
}

// TestACutBackfillStopsThePushReadOfTheRun (forsgren#416): when the budget
// cuts the backfill, the repository is cut short and the push read, which
// comes after it, sends no request in that run, stores nothing and reports
// no pushes cut.
func TestACutBackfillStopsThePushReadOfTheRun(t *testing.T) {
	g, path := withLegacyDeployments(t)
	twoPushes(g)
	g.left[comparePath(shaB, shaD)] = 80
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if r.err != nil || !strings.Contains(r.stderr, "collect: cut short: acme/app: ") {
		t.Fatalf("want acme/app cut short and no error, got %v, %q", r.err, r.stderr)
	}
	if got := g.seen(activityPath); len(got) != 0 {
		t.Errorf("want no push read after the backfill was cut, got %v", got)
	}
	if got := g.seen("/repos/acme/app/compare/"); len(got) != 1 {
		t.Errorf("want the one comparison the budget allowed and no push compare, got %v", got)
	}
	dataOf(path).want(t, PushesFile, "")
	want := Report{BackfillCut: []string{"acme/app"}, Reset: g.resetAt.UTC()}
	if !reflect.DeepEqual(g.report, want) {
		t.Errorf("want the report %+v, got %+v", want, g.report)
	}
}
