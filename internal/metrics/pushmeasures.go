package metrics

// The push measures (forsgren#397, step 4): what the TBD page shows of the
// pushes to main, read from data/pushes.csv and data/push_commits.csv
// (history.Push, history.PushCommit), never from deployments.
//
//   - a push counts in the project whose config lists its repository
//     (ignoring case) when it was pushed in the DORA window; Commits are the
//     distinct first-parent commits those pushes brought, by repository
//     (ignoring case) and SHA, a commit brought by two pushes counted once,
//     at the earlier;
//   - the shares of Commits, in whole percent rounded down: PullRequests, the
//     commits a pr_merge push brought or that are the merge commit of a pull
//     request of data/pulls.csv; Direct, all the others; UnknownAuthors, the
//     commits with no login or GitHub's placeholder login (placeholderLogin),
//     whatever else they are; Bots, the commits whose author login ends in
//     [bot] (as the developer count tells a bot), whatever else they are; the
//     counts are kept with the shares;
//   - the time to main of a commit is its push time minus its author date, a
//     negative one counted as 0 (a clock ahead of the push), as lead time for
//     changes counts one; its mean, median and 90th percentile (spread.go);
//   - commits per push is the commits column of the pushes with a known one,
//     a force push or an unreadable compare left out; its mean, median and
//     90th percentile;
//   - a project with a repository whose push read GitHub refused
//     (Data.PushesDenied) is NotReadable; with no data/pushes.csv at all
//     (Data.PushesUncollected) it is Uncollected, unless it is not readable.
//     Neither falls back to deployments.

import (
	"strings"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// PushMeasures is one project's push measures at the render time.
type PushMeasures struct {
	Project string
	// Pushes counts the pushes in the DORA window.
	Pushes int
	// Commits counts the distinct commits those pushes brought; PullRequests,
	// Direct, UnknownAuthors and Bots are the counts behind the shares.
	Commits, PullRequests, Direct, UnknownAuthors, Bots int
	// TimeToMain is the spread of the commits' times to main; its Count is
	// Commits.
	TimeToMain DurationSpread
	// PerPush is the spread of the commits per push, over the pushes with a
	// known count.
	PerPush CountSpread
	// NotReadable says collect was refused the push read of one of the
	// project's repositories; Uncollected that no push file exists.
	NotReadable, Uncollected bool
}

// PullRequestShare is the share of the commits that came through a pull
// request, in whole percent rounded down; 0 without a commit.
func (m PushMeasures) PullRequestShare() int { return share(m.PullRequests, m.Commits) }

// DirectShare is the share of the commits pushed straight to main.
func (m PushMeasures) DirectShare() int { return share(m.Direct, m.Commits) }

// BotShare is the share of the commits whose author is a bot.
func (m PushMeasures) BotShare() int { return share(m.Bots, m.Commits) }

// UnknownAuthorShare is the share of the commits of an unknown author.
func (m PushMeasures) UnknownAuthorShare() int { return share(m.UnknownAuthors, m.Commits) }

// share is part out of whole in whole percent rounded down; 0 for no whole.
func share(part, whole int) int {
	if whole == 0 {
		return 0
	}
	return part * 100 / whole
}

// pushTime is when the pushes that ended at one tip happened (the earliest)
// and whether any was a pull request merge.
type pushTime struct {
	at    time.Time
	merge bool
}

// pushedCommit is a distinct commit the pushes brought: its project, its
// earliest push time and author date, and whether it is a pull request's or
// of an unknown author.
type pushedCommit struct {
	project  int
	at       time.Time
	authored time.Time
	pull     bool
	unknown  bool
	bot      bool
}

// PushMeasuresOf returns the push measures of each project, in the order of
// projects, from the data's stored pushes at the render time now, over its
// DORA window.
func PushMeasuresOf(projects []config.Project, data Data, now time.Time) []PushMeasures {
	index := indexOf(projects)
	out := make([]PushMeasures, len(projects))
	for i, p := range projects {
		out[i].Project = p.Name
	}
	markPushStates(out, index, data)
	tips, perPush := pushesInWindow(out, index, data, now)
	times := make([][]float64, len(out))
	for _, c := range commitsOfPushes(index, data, tips) {
		out[c.project].add(c)
		times[c.project] = append(times[c.project], float64(max(c.at.Sub(c.authored), 0)))
	}
	for i := range out {
		out[i].TimeToMain, out[i].PerPush = durationSpreadOf(times[i]), countSpreadOf(perPush[i])
	}
	return out
}

// markPushStates sets NotReadable on the project of each repository whose
// push read was refused, compared ignoring case, and Uncollected on every
// other project when there is no pushes file.
func markPushStates(out []PushMeasures, index projectIndex, data Data) {
	for repository := range data.PushesDenied {
		if i, ok := index.of(repository); ok {
			out[i].NotReadable = true
		}
	}
	for i := range out {
		out[i].Uncollected = data.PushesUncollected && !out[i].NotReadable
	}
}

// pushesInWindow counts the pushes of the window per project and gives the
// time of the pushes by tip (commitKey of the repository and the after SHA)
// and the known commit counts per project.
func pushesInWindow(out []PushMeasures, index projectIndex, data Data, now time.Time,
) (map[string]pushTime, [][]float64) {
	tips := map[string]pushTime{}
	perPush := make([][]float64, len(out))
	in := data.window()
	for _, p := range data.Pushes {
		i, ok := index.of(p.Repository)
		if !ok || !in.holds(p.PushedAt, now) {
			continue
		}
		out[i].Pushes++
		if p.Commits > 0 {
			perPush[i] = append(perPush[i], float64(p.Commits))
		}
		k := commitKey(p.Repository, p.After)
		held, seen := tips[k]
		tips[k] = pushTime{at: earlierOf(held.at, p.PushedAt, seen),
			merge: held.merge || p.Kind == history.PushKindPRMerge}
	}
	return tips, perPush
}

// earlierOf is the earlier of a and b, b when there is no a (seen is false).
func earlierOf(a, b time.Time, seen bool) time.Time {
	if seen && a.Before(b) {
		return a
	}
	return b
}

// commitsOfPushes are the distinct commits the pushes of tips brought, by
// commitKey: at their earliest push, a pull request's when any push of them
// was a merge or the commit is a pull request's merge commit.
func commitsOfPushes(index projectIndex, data Data, tips map[string]pushTime) map[string]pushedCommit {
	pulled := mergeCommitsOf(data.Pulls)
	commits := map[string]pushedCommit{}
	for _, pc := range data.PushCommits {
		tip, pushed := tips[commitKey(pc.Repository, pc.After)]
		i, listed := index.of(pc.Repository)
		if !pushed || !listed {
			continue
		}
		k := commitKey(pc.Repository, pc.SHA)
		held, seen := commits[k]
		commits[k] = held.merged(seen, i, pc, tip, pulled[k])
	}
	return commits
}

// merged is the commit c brought by the push at tip to project, with what an
// earlier push of it (held, when seen) said: its earliest push time, a pull
// request's when any push of it was a merge or pulled says it is a pull
// request's merge commit.
func (c pushedCommit) merged(seen bool, project int, pc history.PushCommit, tip pushTime, pulled bool,
) pushedCommit {
	return pushedCommit{project: project, at: earlierOf(c.at, tip.at, seen), authored: pc.AuthoredAt,
		pull:    c.pull || tip.merge || pulled,
		unknown: pc.Author == "" || strings.EqualFold(pc.Author, placeholderLogin),
		bot:     strings.HasSuffix(pc.Author, botSuffix)}
}

// add counts the commit c in m.
func (m *PushMeasures) add(c pushedCommit) {
	m.Commits++
	m.PullRequests += boolCount(c.pull)
	m.Direct += boolCount(!c.pull)
	m.UnknownAuthors += boolCount(c.unknown)
	m.Bots += boolCount(c.bot)
}
