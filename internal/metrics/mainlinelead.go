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
//   - Filling (#469) is true while the window holds data from before the
//     change: a push of the window with a line of unknown parents, or a
//     pull request merged in the window, not CreatedStandsIn, with no line in
//     data.PullCommits. It ends by itself once the window lies after the
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

// leadCommit is a distinct commit in main: its project, its earliest time
// there and its author date.
type leadCommit struct {
	project  int
	at       time.Time
	authored time.Time
}

// leadReading is the state of one reading of the data.
type leadReading struct {
	index projectIndex
	data  Data
	out   []MainlineLeadTime
	// tips is the earliest push time by commitKey(repository, after), chain
	// the first-parent lines by the same key, squashes the pull request
	// number by the key of its merge commit, pullCommits the pull commits by
	// pullKey.
	tips        map[string]time.Time
	chain       map[string]int
	squashes    map[string]int64
	pullCommits map[string][]history.PullCommit
	commits     map[string]leadCommit
	squashed    map[string]bool
	merges      map[string]bool
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
	r.markStates()
	r.readPushes(now)
	r.markPullsFilling(now)
	return r.finish()
}

// newLeadReading is a reading of data for projects, nothing read yet.
func newLeadReading(projects []config.Project, data Data) *leadReading {
	r := &leadReading{index: indexOf(projects), data: data, out: make([]MainlineLeadTime, len(projects)),
		tips: map[string]time.Time{}, chain: map[string]int{}, squashes: map[string]int64{},
		pullCommits: map[string][]history.PullCommit{}, commits: map[string]leadCommit{},
		squashed: map[string]bool{}, merges: map[string]bool{}}
	for i, p := range projects {
		r.out[i].Project = p.Name
	}
	for _, p := range data.Pulls {
		r.squashes[commitKey(p.Repository, p.MergeCommit)] = p.Number
	}
	for _, c := range data.PullCommits {
		k := pullKey(c.Repository, c.Number)
		r.pullCommits[k] = append(r.pullCommits[k], c)
	}
	return r
}

// markStates sets NotReadable and Uncollected as markPushStates does.
func (r *leadReading) markStates() {
	for repository := range r.data.PushesDenied {
		if i, ok := r.index.of(repository); ok {
			r.out[i].NotReadable = true
		}
	}
	for i := range r.out {
		r.out[i].Uncollected = r.data.PushesUncollected && !r.out[i].NotReadable
	}
}

// readPushes notes the pushes of the window, then takes the commits of their
// lines.
func (r *leadReading) readPushes(now time.Time) {
	r.notePushes(now)
	for _, pc := range r.data.PushCommits {
		r.chain[commitKey(pc.Repository, pc.After)] += boolCount(pc.FirstParent)
	}
	for _, pc := range r.data.PushCommits {
		if at, pushed := r.tips[commitKey(pc.Repository, pc.After)]; pushed {
			r.take(pc, at)
		}
	}
}

// notePushes notes the time of each push of the window by its tip, and the
// pushes whose commits are unknown.
func (r *leadReading) notePushes(now time.Time) {
	in := r.data.window()
	for _, p := range r.data.Pushes {
		i, ok := r.index.of(p.Repository)
		if !ok || !in.holds(p.PushedAt, now) {
			continue
		}
		r.out[i].UnknownPushes += boolCount(p.Commits == 0)
		k := commitKey(p.Repository, p.After)
		held, seen := r.tips[k]
		r.tips[k] = earlierOf(held, p.PushedAt, seen)
	}
}

// take counts the line pc of a push at the time at: a merge commit is left
// out, a squash commit is replaced by its pull request's commits, any other
// commit counts.
func (r *leadReading) take(pc history.PushCommit, at time.Time) {
	i, _ := r.index.of(pc.Repository)
	r.out[i].Filling = r.out[i].Filling || pc.Parents == history.ParentsUnknown
	k := commitKey(pc.Repository, pc.SHA)
	if pc.Parents >= 2 {
		r.out[i].MergesLeftOut += boolCount(!r.merges[k])
		r.merges[k] = true
		return
	}
	if originals := r.originalsOf(pc); len(originals) > 0 {
		for _, o := range originals {
			r.count(i, commitKey(o.Repository, o.SHA), at, o.AuthoredAt)
			r.out[i].Squashed += boolCount(!r.squashed[commitKey(o.Repository, o.SHA)])
			r.squashed[commitKey(o.Repository, o.SHA)] = true
		}
		return
	}
	r.count(i, k, at, pc.AuthoredAt)
}

// originalsOf are the pull request commits that stand in for the line pc, if
// it is a squash commit with some; none otherwise.
func (r *leadReading) originalsOf(pc history.PushCommit) []history.PullCommit {
	number, merged := r.squashes[commitKey(pc.Repository, pc.SHA)]
	if !merged || !pc.FirstParent || pc.Parents != 1 || r.chain[commitKey(pc.Repository, pc.After)] != 1 {
		return nil
	}
	return r.pullCommits[pullKey(pc.Repository, number)]
}

// count notes the commit k of project i reaching main at at, authored at
// authored; the earliest arrival stays.
func (r *leadReading) count(i int, k string, at, authored time.Time) {
	held, seen := r.commits[k]
	r.commits[k] = leadCommit{project: i, at: earlierOf(held.at, at, seen), authored: authored}
}

// markPullsFilling sets Filling on the project of each pull request merged
// in the window, not created-stood-in, with no pull commits stored.
func (r *leadReading) markPullsFilling(now time.Time) {
	in := r.data.window()
	for _, p := range r.data.Pulls {
		i, ok := r.index.of(p.Repository)
		listed := len(r.pullCommits[pullKey(p.Repository, p.Number)]) > 0
		if ok && in.holds(p.MergedAt, now) && !p.CreatedStandsIn && !listed {
			r.out[i].Filling = true
		}
	}
}

// finish counts the commits into the projects' spreads and returns them.
func (r *leadReading) finish() []MainlineLeadTime {
	times := make([][]float64, len(r.out))
	for _, c := range r.commits {
		times[c.project] = append(times[c.project], float64(max(c.at.Sub(c.authored), 0)))
	}
	for i := range r.out {
		r.out[i].Lead = durationSpreadOf(times[i])
		r.out[i].Commits = r.out[i].Lead.Count
	}
	return r.out
}
