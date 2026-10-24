package metrics

import (
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
