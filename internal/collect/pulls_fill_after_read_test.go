package collect

import (
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/github"
)

// The fill of the commits of the stored pull requests starts only after a
// pull request read that ended whole (forsgren#491): a read cut by the
// request budget or refused in the same run leaves it to the next run, with no
// request, no warning and no report line of its own.

// storedAndListed is a repository whose pull request list has pull 14 as a
// new merged pull request, so the read has commits to ask for; pull 12 is
// stored with no commit lines, the fill's work.
func storedAndListed(t *testing.T) (*gitHub, string) {
	t.Helper()
	g := pullsOnly(t, pull14)
	g.bodies[pull12.commitsPath()] = twoCommits()
	path := historyPath(t)
	dataOf(path).write(t, "pulls.csv", pullsHeader+pull12.line("2026-09-20T10:00:00Z", false))
	return g, path
}

// TestACutPullRequestReadIsNotFollowedByTheFill: the budget stops the read at
// pull 14's commits; stderr says the pull requests were cut short and says
// nothing of the fill, the report has the pull requests and the pushes (the push read still
// runs) but no fill line, pull 12's
// commits are not asked and the repository is not noted as filled.
func TestACutPullRequestReadIsNotFollowedByTheFill(t *testing.T) {
	g, path := storedAndListed(t)
	g.left[pullsPath] = 1
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if r.err != nil || !strings.Contains(r.stderr, "the pull requests were cut short") {
		t.Fatalf("want the read cut short and no error, got %q, %v", r.stderr, r.err)
	}
	if strings.Contains(r.stderr, "pull request commits were cut short") {
		t.Errorf("want no fill warning, got %q", r.stderr)
	}
	g.wantReportOf(t, Report{PullsCut: []string{"acme/app"}, PushesCut: []string{"acme/app"}, Reset: g.resetAt.UTC()})
	if got := g.seen(pull12.commitsPath()); len(got) != 0 {
		t.Errorf("want no commits asked of pull request 12, got %v", got)
	}
	dataOf(path).want(t, PullCommitsFilledFile, "")
}

// TestARefusedPullRequestReadIsNotFollowedByTheFill: a 403 on the list is
// warned once, not twice; the report is empty, pull 12's commits are not asked
// and the repository is not noted as filled.
func TestARefusedPullRequestReadIsNotFollowedByTheFill(t *testing.T) {
	g, path := storedAndListed(t)
	g.deny(pullsPath)
	r := g.collect(t, shop(production), path, github.DefaultMaxPages)
	if got := strings.Count(r.stderr, "its pull requests are not read"); r.err != nil || got != 1 {
		t.Fatalf("want one refused warning and no error, got %d in %q, %v", got, r.stderr, r.err)
	}
	g.wantReportOf(t, Report{})
	if got := g.seen(pull12.commitsPath()); len(got) != 0 {
		t.Errorf("want no commits asked of pull request 12, got %v", got)
	}
	dataOf(path).want(t, PullCommitsFilledFile, "")
}

// TestAWholePullRequestReadIsFollowedByTheFill: the read of pull 14 ends
// whole and the fill runs in the same run: pull 12 is asked and the repository
// noted as filled.
func TestAWholePullRequestReadIsFollowedByTheFill(t *testing.T) {
	g, path := storedAndListed(t)
	if r := g.collect(t, shop(production), path, github.DefaultMaxPages); r.err != nil {
		t.Fatalf("want no error, got %v (stderr %q)", r.err, r.stderr)
	}
	if got := g.seen(pull12.commitsPath()); len(got) == 0 {
		t.Error("want the commits of pull request 12 asked by the fill")
	}
	dataOf(path).want(t, PullCommitsFilledFile, filledNow)
}
