package metrics

// The first-parent judgement of the Mainline Interval (forsgren#254, step 4):
// which stored commits reached the mainline themselves, and when.
//
//   - a deployment's commits are what GitHub's comparison with the deployment
//     before it gave: every commit reachable from the deployed commit and not
//     from the one before, so exactly one of them, the deployed commit, is the
//     parent of none of the others: its tip;
//   - its first-parent chain runs from the tip through each commit's first
//     parent, the line a merge was made on, while that parent is one of the
//     deployment's commits; the commits a merge brought in, through its other
//     parents, are not on it and do not count;
//   - a commit on the chain is placed at its committer date, when it landed;
//     one GitHub gave no committer date is placed at its author date, never
//     at the zero time;
//   - a deployment that has not exactly one tip has no known lineage: its
//     commits keep the old approximation, every one counted and placed at its
//     author date. A deployment stored before the commits format v3 (decision
//     #293) has no parents, so each of its commits is a tip; its only commit,
//     when it has one, is its own chain without a committer date, placed at
//     its author date all the same;
//   - a commit placed at its author date, by either rule, is counted in
//     MainlineInterval.ByAuthorDate, so the cell names it.

import (
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// lineage holds, per deployment whose lineage is known, the SHAs of its
// first-parent chain.
type lineage map[deploymentKey]map[string]bool

// placed is when a counted commit is placed in the Mainline Interval, and
// whether that time is its author date.
type placed struct {
	at       time.Time
	byAuthor bool
}

// lineageOf is the lineage of the deployments of commits: the first-parent
// chain of each deployment that has a known one.
func lineageOf(commits []history.Commit) lineage {
	out := lineage{}
	for k, p := range parentsByDeployment(commits) {
		if tip, ok := tipOf(p); ok {
			out[k] = firstParentChain(p, tip)
		}
	}
	return out
}

// parentsByDeployment is, per deployment, the parents of each of its commits
// by SHA.
func parentsByDeployment(commits []history.Commit) map[deploymentKey]map[string][]string {
	parents := map[deploymentKey]map[string][]string{}
	for _, c := range commits {
		k := keyOf(c.Repository, c.Kind, c.DeploymentID)
		if parents[k] == nil {
			parents[k] = map[string][]string{}
		}
		parents[k][c.SHA] = c.Parents
	}
	return parents
}

// tipOf is the one commit of a deployment, its commits' parents by SHA, that
// no other names as a parent; none when not exactly one is named by none.
func tipOf(parents map[string][]string) (string, bool) {
	named := namedParents(parents)
	var tips []string
	for sha := range parents {
		if !named[sha] {
			tips = append(tips, sha)
		}
	}
	if len(tips) != 1 {
		return "", false
	}
	return tips[0], true
}

// namedParents is the set of SHAs some commit names as a parent.
func namedParents(parents map[string][]string) map[string]bool {
	named := map[string]bool{}
	for _, ps := range parents {
		for _, p := range ps {
			named[p] = true
		}
	}
	return named
}

// firstParentChain is the SHAs from tip through each first parent while it is
// one of the deployment's commits.
func firstParentChain(parents map[string][]string, tip string) map[string]bool {
	chain := map[string]bool{}
	for sha := tip; !chain[sha]; {
		ps, in := parents[sha]
		if !in {
			break
		}
		chain[sha] = true
		if len(ps) == 0 {
			break
		}
		sha = ps[0]
	}
	return chain
}

// known says whether the lineage of c's deployment is known, so its
// first-parent chain is.
func (l lineage) known(c history.Commit) bool {
	_, known := l[keyOf(c.Repository, c.Kind, c.DeploymentID)]
	return known
}

// place says whether c counts in the Mainline Interval, and when.
func (l lineage) place(c history.Commit) (placed, bool) {
	chain, known := l[keyOf(c.Repository, c.Kind, c.DeploymentID)]
	switch {
	case !known:
		return placed{at: c.AuthoredAt, byAuthor: true}, true
	case !chain[c.SHA]:
		return placed{}, false
	case c.CommittedAt.IsZero():
		return placed{at: c.AuthoredAt, byAuthor: true}, true
	}
	return placed{at: c.CommittedAt}, true
}
