package collect

import (
	"errors"
	"net/http"
	"reflect"
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/github"
)

// The fill of the push commits of the stored merge pushes (forsgren#470,
// step 2): the lines of a pr_merge push stored before the push commits format
// v2 have unknown parents and lack the branch commits the merge brought in, so
// once per repository the push is compared again and its lines are replaced by
// the v2 lines collect writes today.

const pushCommitsFilledHeader = "# forsgren push commits filled v1\nrepository,filled_at\n"

// pushFilledNow is the push commits filled file after a run that noted
// acme/app as filled now.
const pushFilledNow = pushCommitsFilledHeader + "acme/app,2026-10-01T00:00:00Z\n"

const (
	pushTime3  = "2026-09-22T10:00:00Z"
	mergeAuth  = "acme-dev"
	mergeStamp = "2026-09-21T09:00:00Z"
)

// linePCUnknown is the push_commits.csv line of a commit stored before the
// parents column: on the chain, its parents empty.
func linePCUnknown(after, sha, author, authored string) string {
	return "acme/app," + after + "," + sha + "," + author + "," + authored + ",true,\n"
}

// mergeFilled are the lines of the merge push of shaD...shaF once its compare
// is read again: the branch commit shaE off the chain, the merge commit shaF
// on it with two parents.
func mergeFilled() string {
	return linePCBranch(shaF, shaE, "", "2026-09-21T08:00:00Z", 1) + linePC(shaF, shaF, mergeAuth, mergeStamp, 2)
}

// mergeCompare is the answer for the compare of shaD...shaF.
func mergeCompare() string {
	return comparisonOf("ahead", 2,
		lineage{authoredBy{authored{shaE, at(21, 8, 0)}, ""}, []string{shaD}, ""},
		lineage{authoredBy{authored{shaF, at(21, 9, 0)}, mergeAuth}, []string{shaD, shaE}, ""})
}

// storedMerges stores a direct push shaA...shaD with legacy lines, the merge
// push shaD...shaF with legacy lines and the merge push shaB...shaC with
// lines that are current (parents known); with legacyC the push shaB...shaC
// has legacy lines instead. The fake answers the compare of shaD...shaF alone
// and lists no activity. It returns the push commits file as stored.
func storedMerges(t *testing.T, legacyC bool) (*gitHub, string, string) {
	t.Helper()
	g := pushesOnly(t)
	g.bodies[comparePath(shaD, shaF)] = mergeCompare()
	path := historyPath(t)
	data := dataOf(path)
	data.write(t, PushesFile, pushesHeader+linePush(pushTime1, shaA, shaD, "push", "false", "1")+
		linePush(pushTime2, shaD, shaF, "pr_merge", "false", "1")+linePush(pushTime3, shaB, shaC, "pr_merge", "false", "1"))
	c := linePC(shaC, shaC, "", "2026-09-20T08:00:00Z", 1)
	if legacyC {
		c = linePCUnknown(shaC, shaC, "", "2026-09-20T08:00:00Z")
	}
	stored := pushCommitsHeader + linePCUnknown(shaD, shaD, "", "2026-09-20T10:00:00Z") +
		linePCUnknown(shaF, shaF, mergeAuth, mergeStamp) + c
	data.write(t, PushCommitsFile, stored)
	return g, path, stored
}

// TestTheFillReplacesTheLinesOfAStoredMergePushWithItsCurrentLines: the merge
// push with unknown parents is compared again and its lines are replaced in
// place by the lines a push read writes today, the branch commit included;
// the direct push, whose lines are unknown too, and the merge push whose
// lines are current are neither compared nor changed; the repository is noted
// as filled, and the push read goes on after the fill.
func TestTheFillReplacesTheLinesOfAStoredMergePushWithItsCurrentLines(t *testing.T) {
	g, path, _ := storedMerges(t, false)
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatalf("want no error, got %v (stderr %q)", r.err, r.stderr)
	}
	data := dataOf(path)
	data.want(t, PushCommitsFile, pushCommitsHeader+linePCUnknown(shaD, shaD, "", "2026-09-20T10:00:00Z")+
		mergeFilled()+linePC(shaC, shaC, "", "2026-09-20T08:00:00Z", 1))
	data.want(t, PushCommitsFilledFile, pushFilledNow)
	if got := g.seen("/repos/acme/app/compare/"); len(got) != 1 || !strings.HasPrefix(got[0], comparePath(shaD, shaF)) {
		t.Errorf("want one compare, of the merge push with unknown parents, got %v", got)
	}
	if got := g.seen(activityPath); len(got) != 1 {
		t.Errorf("want the push read to go on after the fill, got %v", got)
	}
}

// TestTheFillIsDoneOncePerRepositoryForTheMergePushes: a second run, after the
// mark, compares nothing, even with legacy lines back in the file.
func TestTheFillIsDoneOncePerRepositoryForTheMergePushes(t *testing.T) {
	g, path, stored := storedMerges(t, false)
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatal(r.err)
	}
	dataOf(path).write(t, PushCommitsFile, stored)
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatal(r.err)
	}
	if got := g.seen("/repos/acme/app/compare/"); len(got) != 1 {
		t.Errorf("want one compare over two runs, got %v", got)
	}
}

// TestAMergePushWhoseCompareCannotBeUsedKeepsItsLines: a compare GitHub cannot
// find a commit for, a cut one and one that does not reach the push's tip leave
// the old lines as they are and are named on stderr; the fill is still noted.
func TestAMergePushWhoseCompareCannotBeUsedKeepsItsLines(t *testing.T) {
	cases := map[string]func(*gitHub){
		"missing":   func(g *gitHub) { g.status[comparePath(shaD, shaF)] = http.StatusNotFound },
		"cut":       func(g *gitHub) { g.paged[comparePath(shaD, shaF)] = true },
		"not reach": func(g *gitHub) { g.bodies[comparePath(shaD, shaF)] = chain(shaD, shaE) },
	}
	for name, mutate := range cases {
		t.Run(name, func(t *testing.T) {
			g, path, stored := storedMerges(t, false)
			mutate(g)
			maxPages := github.DefaultMaxPages
			if name == "cut" {
				maxPages = 1
			}
			r := g.collect(t, shop(production), path, maxPages)
			if r.err != nil || !strings.Contains(r.stderr, "its lines stay as they are") {
				t.Errorf("want stderr to say the lines stay and no error, got %q, %v", r.stderr, r.err)
			}
			dataOf(path).want(t, PushCommitsFile, stored)
			dataOf(path).want(t, PushCommitsFilledFile, pushFilledNow)
		})
	}
}

// TestTheMergePushFillStopsWithinTheRequestBudgetAndTheNextRunContinues: at
// the margin the merge pushes filled whole are stored, the repository is not
// noted, the push read does not start (it would starve the fill), stderr says
// so, the run does not fail and the report names the repository as incomplete
// for its pushes; the next run fills the rest and reads the pushes.
func TestTheMergePushFillStopsWithinTheRequestBudgetAndTheNextRunContinues(t *testing.T) {
	g, path, _ := storedMerges(t, true)
	g.bodies[comparePath(shaB, shaC)] = chain(shaB, shaC)
	g.left[comparePath(shaD, shaF)] = 250
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if r.err != nil || !strings.Contains(r.stderr, "acme/app: the push commits were cut short") {
		t.Errorf("want stderr to say the fill was cut short and no error, got %q, %v", r.stderr, r.err)
	}
	data := dataOf(path)
	data.want(t, PushCommitsFile, pushCommitsHeader+linePCUnknown(shaD, shaD, "", "2026-09-20T10:00:00Z")+
		mergeFilled()+linePCUnknown(shaC, shaC, "", "2026-09-20T08:00:00Z"))
	data.want(t, PushCommitsFilledFile, "")
	if want := (Report{PushFillCut: []string{"acme/app"}, Reset: g.resetAt.UTC()}); !reflect.DeepEqual(g.report, want) {
		t.Errorf("want the report %+v, got %+v", want, g.report)
	}
	if got := g.seen(activityPath); len(got) != 0 {
		t.Errorf("want no push read after a cut fill, got %v", got)
	}
	g.left = map[string]int{}
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatalf("want no error on the next run, got %v (stderr %q)", r.err, r.stderr)
	}
	data.want(t, PushCommitsFile, pushCommitsHeader+linePCUnknown(shaD, shaD, "", "2026-09-20T10:00:00Z")+
		mergeFilled()+linePC(shaC, shaC, "", "2026-09-20T08:00:00Z", 1))
	data.want(t, PushCommitsFilledFile, pushFilledNow)
}

// TestADeniedMergePushFillWritesThePushesDeniedMarkAndNeverFails: a 403 on a
// compare leaves the lines, notes no fill, writes the repository in
// pushes_denied.csv and does not fail the run, as the push read does.
func TestADeniedMergePushFillWritesThePushesDeniedMarkAndNeverFails(t *testing.T) {
	g, path, stored := storedMerges(t, false)
	g.deny(comparePath(shaD, shaF))
	g.deny(activityPath)
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if r.err != nil || !strings.Contains(r.stderr, "its push commits are not filled") {
		t.Errorf("want stderr to say the fill is not done and no error, got %q, %v", r.stderr, r.err)
	}
	data := dataOf(path)
	data.want(t, PushCommitsFile, stored)
	data.want(t, PushCommitsFilledFile, "")
	data.want(t, PushesDeniedFile, pushesDeniedNow)
}

// TestAMergePushFillGitHubAnswersWronglyFailsTheRepositoryAfterStoringWhatItRead:
// any other error fails the repository, the lines filled before it are stored
// and the repository is not noted.
func TestAMergePushFillGitHubAnswersWronglyFailsTheRepositoryAfterStoringWhatItRead(t *testing.T) {
	g, path, _ := storedMerges(t, true)
	g.bodies[comparePath(shaB, shaC)] = `{"message": "Server Error"}`
	g.status[comparePath(shaB, shaC)] = http.StatusInternalServerError
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if !errors.Is(r.err, ErrFailed) {
		t.Errorf("want ErrFailed, got %v (stderr %q)", r.err, r.stderr)
	}
	data := dataOf(path)
	data.want(t, PushCommitsFile, pushCommitsHeader+linePCUnknown(shaD, shaD, "", "2026-09-20T10:00:00Z")+
		mergeFilled()+linePCUnknown(shaC, shaC, "", "2026-09-20T08:00:00Z"))
	data.want(t, PushCommitsFilledFile, "")
}

// TestAMergePushFillThatCannotBeStoredFailsTheRepositoryAndNotesNoFill: a
// line that cannot be stored (an author that is no GitHub login) is refused
// before anything is written; the repository fails naming push_commits.csv,
// the file stays as it was and the fill is not noted, so the next run fills
// again.
func TestAMergePushFillThatCannotBeStoredFailsTheRepositoryAndNotesNoFill(t *testing.T) {
	g, path, stored := storedMerges(t, false)
	g.bodies[comparePath(shaD, shaF)] = comparisonOf("ahead", 1,
		lineage{authoredBy{authored{shaF, at(21, 9, 0)}, "not a login!"}, []string{shaD}, ""})
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if !errors.Is(r.err, ErrFailed) || !strings.Contains(r.stderr, PushCommitsFile) {
		t.Errorf("want ErrFailed and stderr naming %s, got %v, %q", PushCommitsFile, r.err, r.stderr)
	}
	dataOf(path).want(t, PushCommitsFile, stored)
	dataOf(path).want(t, PushCommitsFilledFile, "")
}

// TestTheFillLeavesTheMergePushesOfAnotherRepositoryToItsOwnRun: a stored merge
// push of a repository this run does not collect is not compared and its lines
// stay as they are.
func TestTheFillLeavesTheMergePushesOfAnotherRepositoryToItsOwnRun(t *testing.T) {
	g, path, stored := storedMerges(t, false)
	data := dataOf(path)
	other := "acme/other," + pushTime1 + "," + shaA + "," + shaB + ",pr_merge,false,1\n"
	data.write(t, PushesFile, pushesHeader+other+linePush(pushTime2, shaD, shaF, "pr_merge", "false", "1"))
	otherLine := "acme/other," + shaB + "," + shaB + ",,2026-09-20T08:00:00Z,true,\n"
	data.write(t, PushCommitsFile, stored+otherLine)
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatalf("want no error, got %v (stderr %q)", r.err, r.stderr)
	}
	if got := g.seen("/repos/acme/other/"); len(got) != 0 {
		t.Errorf("want nothing asked of the other repository, got %v", got)
	}
	data.want(t, PushCommitsFile, pushCommitsHeader+linePCUnknown(shaD, shaD, "", "2026-09-20T10:00:00Z")+
		mergeFilled()+linePC(shaC, shaC, "", "2026-09-20T08:00:00Z", 1)+otherLine)
}
