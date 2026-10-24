package metrics

// The direct column of Mainline Lead Time and the batch size (forsgren#390,
// step 2 of 3): what the pull request column cannot see, the work that goes
// straight to the trunk. Both read data/commits.csv; the first-parent chain
// is the Mainline Interval's (lineage.go).
//
//   - a direct commit is a commit of a deployment's first-parent chain that
//     is not the merge commit of a pull request of data/pulls.csv (decision
//     #392): compared by repository, ignoring case, and SHA, for every pull
//     request whatever its window or author; the commits a merge brought in
//     are off the chain, so they never count here;
//   - its time to main is its author date to the deployment that first
//     contains it, the earliest of the deployments that count it, a negative
//     time counted as 0 (forsgren sees no push time); the commit counts when
//     that deployment was created in the DORA window, once by repository
//     (ignoring case) and SHA; the result is their median and count;
//   - a commit of a deployment without a known lineage is taken as direct at
//     its author date, and ByAuthorDate counts it (decision #391);
//   - the batch size of a deployment is the number of commits it brought to
//     the first-parent chain, direct and merge commits alike (decision
//     #393); the result is the median of the deployments created in the
//     window, the mean of the two middle ones for an even count, so x.5; a
//     deployment without a known lineage is left out and counted in Legacy.

import (
	"slices"
	"strings"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// MainlineDirect is one project's time to main of the commits pushed straight
// to the trunk, at the render time.
type MainlineDirect struct {
	Project string
	// Commits counts the distinct direct commits whose deployment was created
	// in the DORA window.
	Commits int
	// Median is the median of the times from a commit's author date to the
	// deployment that first contains it; zero without a commit.
	Median time.Duration
	// ByAuthorDate counts the commits of deployments without a known lineage,
	// taken as direct.
	ByAuthorDate int
}

// HasDirect says whether a direct commit counted, so a median to show.
func (m MainlineDirect) HasDirect() bool { return m.Commits > 0 }

// directTime is a direct commit's first deployment: when it was created, the
// time to main, whether its lineage is unknown, and the commit's project.
type directTime struct {
	deployed time.Time
	lead     time.Duration
	legacy   bool
	project  int
}

// MainlineDirects returns the direct time to main of each project, in the
// order of projects, from the data's stored commits at the render time now,
// over its DORA window.
func MainlineDirects(projects []config.Project, data Data, now time.Time) []MainlineDirect {
	counting := directCounting{index: indexOf(projects), lines: lineageOf(data.Commits),
		pulled: mergeCommitsOf(data.Pulls)}
	first := map[string]directTime{}
	for _, c := range data.Commits {
		i, ok := counting.project(c)
		key := commitKey(c.Repository, c.SHA)
		if !ok {
			continue
		}
		if seen, held := first[key]; !held || c.DeployedAt.Before(seen.deployed) {
			first[key] = directTime{c.DeployedAt, leadTimeOf(c), !counting.lines.known(c), i}
		}
	}
	return directsOf(projects, first, data.window(), now)
}

// directCounting is what says whether a stored commit is direct: the
// projects' repositories, the lineage of the deployments and the merge
// commits of the pull requests.
type directCounting struct {
	index  projectIndex
	lines  lineage
	pulled map[string]bool
}

// project is the index of the project whose direct commit c is, and whether c
// is one: its repository is listed, it is on its deployment's first-parent
// chain (or the lineage is unknown), and it is no pull request's merge commit.
func (d directCounting) project(c history.Commit) (int, bool) {
	i, listed := d.index.of(c.Repository)
	_, onChain := d.lines.place(c)
	return i, listed && onChain && !d.pulled[commitKey(c.Repository, c.SHA)]
}

// directsOf are the projects' MainlineDirects over the first deployment of
// each commit, those created in window at now.
func directsOf(projects []config.Project, first map[string]directTime, in window, now time.Time,
) []MainlineDirect {
	leads := make([][]time.Duration, len(projects))
	out := make([]MainlineDirect, len(projects))
	for i, p := range projects {
		out[i].Project = p.Name
	}
	for _, d := range first {
		if in.holds(d.deployed, now) {
			leads[d.project] = append(leads[d.project], d.lead)
			out[d.project].ByAuthorDate += boolCount(d.legacy)
		}
	}
	for i, l := range leads {
		out[i].Commits, out[i].Median = len(l), medianOrZero(l)
	}
	return out
}

// medianOrZero is the median of leads, 0 for none.
func medianOrZero(leads []time.Duration) time.Duration {
	if len(leads) == 0 {
		return 0
	}
	return median(leads)
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

// BatchSize is one project's commits per deployment, at the render time.
type BatchSize struct {
	Project string
	// Deployments counts the deployments created in the DORA window whose
	// lineage is known.
	Deployments int
	// Median is the median number of first-parent commits per deployment.
	Median float64
	// Legacy counts the deployments in the window left out for want of a
	// known lineage.
	Legacy int
}

// HasBatch says whether a deployment counted, so a median to show.
func (b BatchSize) HasBatch() bool { return b.Deployments > 0 }

// batch is one deployment's project, creation time and first-parent commits,
// and whether its lineage is known.
type batch struct {
	project  int
	deployed time.Time
	commits  int
	known    bool
}

// BatchSizes returns the batch size of each project, in the order of
// projects, from the data's stored commits at the render time now, over its
// DORA window.
func BatchSizes(projects []config.Project, data Data, now time.Time) []BatchSize {
	index := indexOf(projects)
	lines := lineageOf(data.Commits)
	batches := map[deploymentKey]*batch{}
	for _, c := range data.Commits {
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
	return batchSizesOf(projects, batches, data.window(), now)
}

// batchSizesOf are the projects' BatchSizes over the deployments created in
// window at now.
func batchSizesOf(projects []config.Project, batches map[deploymentKey]*batch, in window, now time.Time,
) []BatchSize {
	sizes := make([][]int, len(projects))
	out := make([]BatchSize, len(projects))
	for i, p := range projects {
		out[i].Project = p.Name
	}
	for _, b := range batches {
		switch {
		case !in.holds(b.deployed, now):
		case !b.known:
			out[b.project].Legacy++
		default:
			sizes[b.project] = append(sizes[b.project], b.commits)
		}
	}
	for i, s := range sizes {
		out[i].Deployments = len(s)
		out[i].Median = medianCount(s)
	}
	return out
}

// medianCount is the middle of counts, or the mean of the two middle ones when
// the number is even; 0 for none.
func medianCount(counts []int) float64 {
	if len(counts) == 0 {
		return 0
	}
	sorted := slices.Sorted(slices.Values(counts))
	mid := len(sorted) / 2
	if len(sorted)%2 == 1 {
		return float64(sorted[mid])
	}
	return float64(sorted[mid-1]+sorted[mid]) / 2
}
