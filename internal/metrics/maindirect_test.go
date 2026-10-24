package metrics

import (
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// trunkCommit is a commit of acme/app in the deployment id, deployed deployedAgo
// before now, authored lead before the deployment, with parents, the first
// parent first; its committer date is the author date.
func trunkCommit(id int64, sha string, deployedAgo, lead time.Duration, parents ...string) history.Commit {
	deployed := now.Add(-deployedAgo)
	authored := deployed.Add(-lead)
	return history.Commit{
		Repository: "acme/app", Kind: history.KindEnvironment, DeploymentID: id, SHA: sha,
		AuthoredAt: authored, CommittedAt: authored, DeployedAt: deployed, Parents: parents,
	}
}

// pullMergedAs is a pull request of acme/app whose merge made the commit sha.
func pullMergedAs(sha string) history.PullRequest {
	p := mergedPull("acme/app", 1, 3*time.Hour, 2*time.Hour)
	p.MergeCommit = sha
	return p
}

// trunkData are three deployments of acme/app: 1 a direct push of two commits
// deployed 20 minutes after they were authored; 2 a pull request merged with
// a merge commit (the branch commit p1 is on the merge's second-parent side,
// the merge commit m is on the chain), authored days before; 3 a legacy
// deployment, no parents, two commits authored 40 and 60 minutes before it.
func trunkData() Data {
	m := time.Minute
	return Data{
		Commits: []history.Commit{
			trunkCommit(1, "d1", 3*time.Hour, 20*m, "base"),
			trunkCommit(1, "d2", 3*time.Hour, 20*m, "d1"),
			trunkCommit(2, "p1", 2*time.Hour, 72*time.Hour, "d2"),
			trunkCommit(2, "m", 2*time.Hour, 0, "d2", "p1"),
			trunkCommit(3, "l1", time.Hour, 40*m),
			trunkCommit(3, "l2", time.Hour, 60*m),
		},
		Pulls: []history.PullRequest{pullMergedAs("m")},
	}
}

// TestMainlineDirectIsTheTimeToMainOfCommitsNotInAPullRequest (forsgren#390,
// step 1): the direct commits d1 and d2 (20 min each) and the legacy
// deployment's l1 and l2 (40 and 60 min, at their author date, named): median
// 30 min of 4; the pull request's merge commit m and its branch commit p1,
// authored three days before, are left out.
func TestMainlineDirectIsTheTimeToMainOfCommitsNotInAPullRequest(t *testing.T) {
	got := MainlineDirects(projects, trunkData(), now)[0]
	want := MainlineDirect{Project: "Acme Shop", Commits: 4, Median: 30 * time.Minute, ByAuthorDate: 2}
	if got != want {
		t.Errorf("want %+v, got %+v", want, got)
	}
}

// TestMainlineDirectHasNothingForAProjectOfPullRequestsOnly (forsgren#390,
// step 1): a project whose only deployment is a pull request has no direct
// commit, so nothing to show.
func TestMainlineDirectHasNothingForAProjectOfPullRequestsOnly(t *testing.T) {
	data := trunkData()
	data.Commits = data.Commits[2:4]
	got := MainlineDirects(projects, data, now)[0]
	if got.HasDirect() || got.Commits != 0 {
		t.Errorf("want no direct commit, got %+v", got)
	}
}

// TestMainlineDirectCountsACommitAuthoredAfterItsDeploymentAsZero (forsgren#390,
// step 1): a clock ahead of the deployment is a time of 0, as lead time for
// changes counts one, and the commit stays in the count.
func TestMainlineDirectCountsACommitAuthoredAfterItsDeploymentAsZero(t *testing.T) {
	data := Data{Commits: []history.Commit{trunkCommit(1, "c1", time.Hour, -10*time.Minute, "base")}}
	got := MainlineDirects(projects, data, now)[0]
	if want := (MainlineDirect{Project: "Acme Shop", Commits: 1}); got != want {
		t.Errorf("want one commit at 0, got %+v", got)
	}
}

// TestMainlineDirectTimesACommitAtItsFirstDeployment (forsgren#390, step 1):
// the same commit shipped by two deployments (two environments) is timed at
// the earlier one: authored 30 min before the first, so 30 min, not 150.
func TestMainlineDirectTimesACommitAtItsFirstDeployment(t *testing.T) {
	first := trunkCommit(1, "c1", 3*time.Hour, 30*time.Minute, "base")
	later := first
	later.DeploymentID, later.DeployedAt = 2, now.Add(-time.Hour)
	got := MainlineDirects(projects, Data{Commits: []history.Commit{later, first}}, now)[0]
	if want := (MainlineDirect{Project: "Acme Shop", Commits: 1, Median: 30 * time.Minute}); got != want {
		t.Errorf("want 1 commit at 30 min, got %+v", got)
	}
}

// TestBatchSizeIsTheFirstParentCommitsPerDeployment (forsgren#390, step 1):
// the direct push brought 2 commits to main, the pull request 1 (its merge
// commit; the branch commit is on the other side), median 1.5 of 2
// deployments; the legacy deployment has no known chain, so it is left out and
// counted apart.
func TestBatchSizeIsTheFirstParentCommitsPerDeployment(t *testing.T) {
	got := BatchSizes(projects, trunkData(), now)[0]
	want := BatchSize{Project: "Acme Shop", Deployments: 2, Median: 1.5, Legacy: 1}
	if got != want {
		t.Errorf("want %+v, got %+v", want, got)
	}
}
