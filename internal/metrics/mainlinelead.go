package metrics

// The Mainline Lead Time (forsgren#463, step 7): how long the commits that
// reached main took from their author date to main, read from the pushes
// (data/pushes.csv, data/push_commits.csv) and, for a squash merge, the pull
// request's own commits (data/pull_commits.csv). The rulings are Yves's, on
// the decision issues named:
//
//   - the pushes count when pushed in the DORA window, in the project whose
//     config lists their repository (ignoring case), as PushMeasuresOf;
//   - the commits are the lines of those pushes, first-parent or not,
//     distinct by repository (ignoring case) and SHA, each at its earliest
//     push time (#466: the earliest arrival wins);
//   - a commit with two parents or more, a merge commit, is left out and
//     counted in MergesLeftOut; its branch commits stay (#464). A line whose
//     parent count is unknown (from before the change) is counted;
//   - a squash commit (#465) is a first-parent commit of one parent, the only
//     first-parent line of its push, that IS the merge commit of a pull
//     request of data.Pulls in the same repository (ignoring case); the pull
//     request's commits then stand in for it, never both: each original at
//     the squash commit's push time (the earliest if the original arrived
//     otherwise too), from its own author date, counted in Squashed. A pull
//     request with no pull commits (stored before the change) leaves the
//     squash commit an ordinary commit. A squash whose push is not stored
//     brings nothing: no merged_at stands in (#466);
//   - every commit counts, a bot's too (#467);
//   - the lead time of a commit is its time in main minus its author date, a
//     negative one counted as 0; the spread is durationSpreadOf's, and
//     Commits the count;
//   - the pushes of the window whose commit count is unknown (Commits 0: a
//     cut or failed compare, a force push) bring no commits and are counted
//     in UnknownPushes: their commits are left out because the data is
//     incomplete, not counted as 0 (#468);
//   - Filling (#469, #476) is true while the window holds data from before
//     the change that lost something: a pr_merge push of the window with a
//     line of unknown parents (its branch commits are missing; a tip several
//     pushes share counts as a merge push when any of them is one), or a
//     pull request merged in the window, not CreatedStandsIn, with no line in
//     data.PullCommits. A direct push with unknown parents lost nothing and
//     does not set it. It ends by itself once the window lies after the
//     change; no state is kept;
//   - NotReadable (a repository in Data.PushesDenied) and Uncollected
//     (Data.PushesUncollected, unless NotReadable) are as PushMeasures'.

import (
	"fmt"
	"strings"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// MainlineLeadTime is one project's Mainline Lead Time at the render time.
type MainlineLeadTime struct {
	Project string
	// Commits counts the distinct commits that reached main in the window;
	// Lead is the spread of their lead times, its Count is Commits.
	Commits int
	Lead    DurationSpread
	// Squashed counts the originals that stood in for a squash commit,
	// MergesLeftOut the merge commits left out, UnknownPushes the pushes of
	// the window whose commits are unknown.
	Squashed, MergesLeftOut, UnknownPushes int
	// Filling says the window holds data from before the change.
	Filling bool
	// NotReadable says collect was refused the push read of one of the
	// project's repositories; Uncollected that no push file exists.
	NotReadable, Uncollected bool
}

// leadReading is the state of one reading of the data: the projects' lead
// times so far (out), the earliest push time by tip (commitKey of the
// repository and the after SHA), the tips of the merge pushes (mergeTips), what tells the squash commits (squash), the
// distinct commits in main by commitKey, and the originals and merge commits
// already counted.
type leadReading struct {
	index            projectIndex
	data             Data
	out              []MainlineLeadTime
	tips             map[string]time.Time
	mergeTips        map[string]bool
	squash           squashes
	commits          map[string]mainArrival
	squashed, merges map[string]bool
}

// squashes is what tells a squash commit and its originals apart: the
// first-parent lines of each push by its tip's commitKey (chain), the pull
// request number by the commitKey of its merge commit (merged), and the pull
// commits by pullKey.
type squashes struct {
	chain       map[string]int
	merged      map[string]int64
	pullCommits map[string][]history.PullCommit
}

// pullKey is a pull request's identity: its repository, lower-case, and number.
func pullKey(repository string, number int64) string {
	return fmt.Sprintf("%s#%d", strings.ToLower(repository), number)
}

// MainlineLeadTimesOf returns the Mainline Lead Time of each project, in the
// order of projects, from the data's stored pushes and pull commits at the
// render time now, over its DORA window.
func MainlineLeadTimesOf(projects []config.Project, data Data, now time.Time) []MainlineLeadTime {
	r := newLeadReading(projects, data)
	r.readPushes(now)
	r.markPullsFilling(now)
	return r.finish()
}

// newLeadReading is a reading of data for projects, their push states set,
// nothing read yet.
func newLeadReading(projects []config.Project, data Data) *leadReading {
	r := &leadReading{index: indexOf(projects), data: data, out: make([]MainlineLeadTime, len(projects)),
		tips: map[string]time.Time{}, mergeTips: map[string]bool{}, squash: squashesOf(data),
		commits: map[string]mainArrival{}, squashed: map[string]bool{}, merges: map[string]bool{}}
	for i, s := range pushStatesOf(r.index, data, len(projects)) {
		r.out[i] = MainlineLeadTime{Project: projects[i].Name, NotReadable: s.notReadable, Uncollected: s.uncollected}
	}
	return r
}

// squashesOf is the squash lookups of data's pull requests, pull commits and
// push commits.
func squashesOf(data Data) squashes {
	s := squashes{chain: map[string]int{}, merged: map[string]int64{}, pullCommits: map[string][]history.PullCommit{}}
	for _, p := range data.Pulls {
		s.merged[commitKey(p.Repository, p.MergeCommit)] = p.Number
	}
	for _, c := range data.PullCommits {
		k := pullKey(c.Repository, c.Number)
		s.pullCommits[k] = append(s.pullCommits[k], c)
	}
	for _, pc := range data.PushCommits {
		s.chain[commitKey(pc.Repository, pc.After)] += boolCount(pc.FirstParent)
	}
	return s
}

// originalsOf are the pull request commits that stand in for the line pc, if
// it is a squash commit with some; none otherwise.
func (s squashes) originalsOf(pc history.PushCommit) []history.PullCommit {
	number, merged := s.merged[commitKey(pc.Repository, pc.SHA)]
	if !merged || !s.aloneOnChain(pc) {
		return nil
	}
	return s.pullCommits[pullKey(pc.Repository, number)]
}

// aloneOnChain says the line pc is a commit of one parent and the only
// first-parent line of its push.
func (s squashes) aloneOnChain(pc history.PushCommit) bool {
	return pc.FirstParent && pc.Parents == 1 && s.chain[commitKey(pc.Repository, pc.After)] == 1
}

// unlisted says the pull request p has no pull commits stored and its first
// commit time is not the created time's: it was stored before the change.
func (s squashes) unlisted(p history.PullRequest) bool {
	return !p.CreatedStandsIn && len(s.pullCommits[pullKey(p.Repository, p.Number)]) == 0
}

// readPushes notes the pushes of the window, then takes the commits of their
// lines.
func (r *leadReading) readPushes(now time.Time) {
	r.notePushes(now)
	for _, pc := range r.data.PushCommits {
		if at, pushed := r.tips[commitKey(pc.Repository, pc.After)]; pushed {
			r.take(pc, at)
		}
	}
}

// notePushes notes the time of each push of the window by its tip, the tips
// of merge pushes, and the pushes whose commits are unknown.
func (r *leadReading) notePushes(now time.Time) {
	forPushesInWindow(r.index, r.data, now, func(i int, p history.Push) {
		r.out[i].UnknownPushes += boolCount(p.Commits == 0)
		k := commitKey(p.Repository, p.After)
		held, seen := r.tips[k]
		r.tips[k] = earlierOf(held, p.PushedAt, seen)
		r.mergeTips[k] = r.mergeTips[k] || p.Kind == history.PushKindPRMerge
	})
}

// take counts the line pc of a push at the time at: a merge commit is left
// out, a squash commit is replaced by its pull request's commits, any other
// commit counts.
func (r *leadReading) take(pc history.PushCommit, at time.Time) {
	i, _ := r.index.of(pc.Repository)
	r.out[i].Filling = r.out[i].Filling || r.lostBranch(pc)
	switch originals := r.squash.originalsOf(pc); {
	case pc.Parents >= 2:
		r.out[i].MergesLeftOut += firstMark(r.merges, commitKey(pc.Repository, pc.SHA))
	case len(originals) > 0:
		r.takeOriginals(i, originals, at)
	default:
		r.count(i, commitKey(pc.Repository, pc.SHA), at, pc.AuthoredAt)
	}
}

// lostBranch says the line pc has unknown parents and belongs to a merge
// push, which lost its branch commits before the change (#476).
func (r *leadReading) lostBranch(pc history.PushCommit) bool {
	return pc.Parents == history.ParentsUnknown && r.mergeTips[commitKey(pc.Repository, pc.After)]
}

// takeOriginals counts the originals of a squash commit of project i pushed
// at at, each from its own author date.
func (r *leadReading) takeOriginals(i int, originals []history.PullCommit, at time.Time) {
	for _, o := range originals {
		k := commitKey(o.Repository, o.SHA)
		r.count(i, k, at, o.AuthoredAt)
		r.out[i].Squashed += firstMark(r.squashed, k)
	}
}

// firstMark marks k in marked: 1 the first time, 0 after.
func firstMark(marked map[string]bool, k string) int {
	first := !marked[k]
	marked[k] = true
	return boolCount(first)
}

// count notes the commit k of project i reaching main at at, authored at
// authored; the earliest arrival stays.
func (r *leadReading) count(i int, k string, at, authored time.Time) {
	held, seen := r.commits[k]
	r.commits[k] = mainArrival{project: i, at: earlierOf(held.at, at, seen), authored: authored}
}

// markPullsFilling sets Filling on the project of each pull request merged
// in the window that is unlisted.
func (r *leadReading) markPullsFilling(now time.Time) {
	in := r.data.window()
	for _, p := range r.data.Pulls {
		if i, ok := r.index.of(p.Repository); ok && in.holds(p.MergedAt, now) {
			r.out[i].Filling = r.out[i].Filling || r.squash.unlisted(p)
		}
	}
}

// finish counts the commits into the projects' spreads and returns them.
func (r *leadReading) finish() []MainlineLeadTime {
	times := make([][]float64, len(r.out))
	for _, c := range r.commits {
		times[c.project] = append(times[c.project], c.timeInMain())
	}
	for i := range r.out {
		r.out[i].Lead = durationSpreadOf(times[i])
		r.out[i].Commits = r.out[i].Lead.Count
	}
	return r.out
}
