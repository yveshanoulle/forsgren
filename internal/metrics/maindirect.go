package metrics

// What the deployment measures (deploymeasures.go) and the push measures
// (pushmeasures.go) share of the first version of the TBD page's direct and
// batch size columns (forsgren#390), which the groups of forsgren#397
// replaced: the first-parent chain is the Mainline Interval's (lineage.go).
//
//   - a commit counts at the earliest deployment that contains it
//     (firstDeployments), timed from its author date to that deployment, a
//     negative time counted as 0 (leadTimeOf); a commit of a deployment
//     without a known lineage is taken at its author date and flagged;
//   - the batch of a deployment is the number of commits it brought to the
//     first-parent chain, and whether its lineage is known (batchesOf).

import (
	"strings"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// directTime is a commit's first deployment: when it was created, the time to
// deploy, whether its lineage is unknown, and the commit's project.
type directTime struct {
	deployed time.Time
	lead     time.Duration
	legacy   bool
	project  int
}

// directCounting is what says whether a stored commit counts: the projects'
// repositories and the lineage of the deployments.
type directCounting struct {
	index projectIndex
	lines lineage
}

// project is the index of the project whose commit c is, and whether it
// counts: its repository is listed and it is on its deployment's first-parent
// chain (or the lineage is unknown).
func (d directCounting) project(c history.Commit) (int, bool) {
	i, listed := d.index.of(c.Repository)
	_, onChain := d.lines.place(c)
	return i, listed && onChain
}

// firstDeployments are the commits that counting accepts, by commitKey, each
// at the earliest deployment that contains it.
func firstDeployments(commits []history.Commit, counting directCounting) map[string]directTime {
	first := map[string]directTime{}
	for _, c := range commits {
		i, ok := counting.project(c)
		key := commitKey(c.Repository, c.SHA)
		if !ok {
			continue
		}
		if seen, held := first[key]; !held || c.DeployedAt.Before(seen.deployed) {
			first[key] = directTime{c.DeployedAt, leadTimeOf(c), !counting.lines.known(c), i}
		}
	}
	return first
}

// commitKey is a commit's identity: its repository, lower-case, and SHA.
func commitKey(repository, sha string) string { return strings.ToLower(repository) + "@" + sha }

// mergeCommitsOf are the merge commits of pulls, by commitKey.
func mergeCommitsOf(pulls []history.PullRequest) map[string]bool {
	merged := map[string]bool{}
	for _, p := range pulls {
		merged[commitKey(p.Repository, p.MergeCommit)] = true
	}
	return merged
}

// batch is one deployment's project, creation time and first-parent commits,
// and whether its lineage is known.
type batch struct {
	project  int
	deployed time.Time
	commits  int
	known    bool
}

// batchesOf are the deployments of the listed repositories' commits, each with
// its first-parent commits.
func batchesOf(commits []history.Commit, index projectIndex) map[deploymentKey]*batch {
	lines := lineageOf(commits)
	batches := map[deploymentKey]*batch{}
	for _, c := range commits {
		i, ok := index.of(c.Repository)
		if !ok {
			continue
		}
		k := keyOf(c.Repository, c.Kind, c.DeploymentID)
		if batches[k] == nil {
			batches[k] = &batch{project: i, deployed: c.DeployedAt, known: lines.known(c)}
		}
		_, counts := lines.place(c)
		batches[k].commits += boolCount(counts)
	}
	return batches
}
