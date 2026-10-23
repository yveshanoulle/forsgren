package collect

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/github"
)

// The refused pull request reads (forsgren#337, decision #332): a
// repository's line in data/pulls_denied.csv, written on a 403 and cleared
// by a read that works, kept apart from a budget stop, a failed read and a
// repository with no pull requests.

const (
	pullsDeniedHeader = "# forsgren pulls denied v1\nrepository,denied_at\n"
	// deniedNow is the pulls denied file after a run that was refused
	// acme/app's pull requests.
	deniedNow = pullsDeniedHeader + "acme/app,2026-10-01T00:00:00Z\n"
	// deniedBefore is the pulls denied file of an earlier refused run, with
	// a line of another repository that the run does not read.
	deniedBefore = pullsDeniedHeader + "acme/app,2026-09-20T08:00:00Z\nacme/lib,2026-09-20T08:00:00Z\n"
	// otherDenied is deniedBefore with acme/app's line cleared.
	otherDenied = pullsDeniedHeader + "acme/lib,2026-09-20T08:00:00Z\n"
)

// wantNoToken fails when the file name in d holds the fake's token value.
func (d dataDir) wantNoToken(t *testing.T, name string) {
	t.Helper()
	raw, _ := os.ReadFile(filepath.Clean(filepath.Join(string(d), name)))
	if strings.Contains(string(raw), "sesame") {
		t.Errorf("want no token value in %s, got %q", name, raw)
	}
}

// TestARefusedPullRequestReadIsNotedWithItsTime: a 403 on the list or on a
// pull request's commits writes the repository and the run's time, whole
// seconds UTC, and nothing else; an older line of it is moved to now. The
// repository is not in the report's pulls-cut lines: a refusal is not a
// budget stop.
func TestARefusedPullRequestReadIsNotedWithItsTime(t *testing.T) {
	for _, c := range []refusal{
		{"the list, no file yet", "", pullsPath, deniedNow},
		{"the list, an older refusal", deniedBefore, pullsPath, deniedNow + "acme/lib,2026-09-20T08:00:00Z\n"},
		{"a commit list", "", pull12.commitsPath(), deniedNow},
	} {
		t.Run(c.name, c.check)
	}
}

// refusal is a run GitHub refuses a path of acme/app's pull requests in:
// the pulls denied file before it (empty for none), the refused path, and
// the file wanted after it.
type refusal struct {
	name, before, denied, want string
}

// check fails unless the run leaves c.want, with no token value, and no
// pulls-cut line in the report.
func (c refusal) check(t *testing.T) {
	g := pullsOnly(t, pull12)
	g.deny(c.denied)
	path := historyPath(t)
	data := dataOf(path)
	if c.before != "" {
		data.write(t, PullsDeniedFile, c.before)
	}
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatalf("want no error, got %v (stderr %q)", r.err, r.stderr)
	}
	data.want(t, PullsDeniedFile, c.want)
	data.wantNoToken(t, PullsDeniedFile)
	if len(g.report.PullsCut) != 0 {
		t.Errorf("want a refusal kept apart from a budget stop, got the report %+v", g.report)
	}
}

// TestAPullRequestReadThatWorksClearsTheRefusal: a read that GitHub answers,
// with merged pull requests, with none at all, or cut at the page limit
// (decision on #337: a read that ends without an error clears), removes the
// repository's line and leaves the others.
func TestAPullRequestReadThatWorksClearsTheRefusal(t *testing.T) {
	for _, c := range []struct {
		name     string
		pulls    []pull
		maxPages int
		paged    bool
	}{
		{"merged pull requests", []pull{pull12}, github.DefaultMaxPages, false},
		{"no pull requests", nil, github.DefaultMaxPages, false},
		{"a list cut at the page limit", []pull{pull12}, 1, true},
	} {
		t.Run(c.name, func(t *testing.T) {
			g := pullsOnly(t, c.pulls...)
			g.paged[pullsPath] = c.paged
			path := historyPath(t)
			data := dataOf(path)
			data.write(t, PullsDeniedFile, deniedBefore)
			if r := g.collect(t, shop(production), path, c.maxPages); r.err != nil {
				t.Fatalf("want no error, got %v (stderr %q)", r.err, r.stderr)
			}
			data.want(t, PullsDeniedFile, otherDenied)
		})
	}
}

// TestABudgetStopOrAFailedReadLeavesTheRefusalsAsTheyWere: a read stopped at
// the request budget or failed by a wrong answer neither clears an earlier
// refusal nor notes a new one: neither says whether the token may read the
// pull requests.
func TestABudgetStopOrAFailedReadLeavesTheRefusalsAsTheyWere(t *testing.T) {
	for _, before := range []string{deniedBefore, ""} {
		for name, g := range map[string]*gitHub{"budget": budgetStop(t), "wrong answer": wrongAnswer(t)} {
			t.Run(name, func(t *testing.T) {
				path := historyPath(t)
				data := dataOf(path)
				if before != "" {
					data.write(t, PullsDeniedFile, before)
				}
				g.collect(t, shop(production), path, github.DefaultMaxPages)
				data.want(t, PullsDeniedFile, before)
			})
		}
	}
}

// budgetStop is a fake whose request budget reaches its margin before the
// commits of acme/app's second pull request.
func budgetStop(t *testing.T) *gitHub {
	t.Helper()
	g := pullsOnly(t, pull14, pull12)
	g.left[pullsPath] = 300
	g.left[pull14.commitsPath()] = 251
	return g
}

// wrongAnswer is a fake that lists a pull request with no number.
func wrongAnswer(t *testing.T) *gitHub {
	t.Helper()
	g := pullsOnly(t)
	g.bodies[pullsPath] = list(`{"number": 0}`)
	return g
}
