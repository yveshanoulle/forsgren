package metrics

// PR Lead Time (forsgren#256, step 1 of 3) is the second number of the
// TBD page: how old a change is when it reaches the trunk, read with the
// Mainline Interval (short/short, short/long: long-lived branches, and so
// on). It reads the merged pull requests `forsgren collect` stores in
// data/pulls.csv (history.PullRequest), so work pushed straight to the main
// branch is not in it.
//
//   - one lead time per merged pull request, never per commit (decision
//     #302): its merged time minus its first commit time, the earliest git
//     author date of its commits (decision #297);
//   - a pull request counts when it was merged in the DORA window (dora_days,
//     both ends included, the window every DORA number counts in), whatever
//     its first commit's age, in the project whose config lists its
//     repository, compared ignoring case; pulls.csv holds merged pull
//     requests only, and one without a merged time is not counted;
//   - a first commit time of a cut commit list (decision #299) is kept: it may
//     be too late, so that lead time is a lower bound, and it counts in the
//     mean all the same; Cut says how many counted, so the mean is not shown
//     as exact when it holds any;
//   - when the commit list gave no usable date (decision #300) the created
//     time stands in for the first commit time, counted, and CreatedStandsIn
//     says how many;
//   - a first commit authored after the merge (a clock, a rewritten date) is
//     a lead time of 0, as lead time for changes counts one: the pull request
//     is a real integration and stays in the count;
//   - the mean is the mean of the lead times, their median (the mean of the two
//     middle ones for an even count) is shown from two pull requests and their
//     90th percentile, by nearest rank, from minP90Gaps (forsgren#423, Yves on
//     #432), as every other spread of the TBD page; the deviation and the share
//     merged within 24 hours are gone from the page (forsgren#423);
//   - only the pull requests a person opened count (forsgren#345, step 2,
//     Yves's answers on #341, #348 and #349: history.ByHuman), in the mean,
//     the median, the count and the notes; one a bot opened (ByBot) and
//     one whose author's account type is not known (BotUnknown, every line
//     of the pulls format v1 among them) are left out, never taken as human,
//     and the bots' counted apart in Bots (the others are not counted at all,
//     forsgren#403), merged in the window like the others;
//   - a project with a repository whose pull request read GitHub refused
//     (Data.PullsDenied, data/pulls_denied.csv, forsgren#337) is NotReadable
//     as a whole, whatever was read of its other repositories.
//
// The result is per project; the TBD page's column (step 2) writes it with
// its cells, prleadtimecell.go.

import (
	"math"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// PRLeadTime is one project's PR Lead Time at the render time.
type PRLeadTime struct {
	Project string
	// PullRequests counts the human pull requests merged in the DORA window,
	// the ones every other number here is of.
	PullRequests int
	// Mean is the mean lead time; zero without a pull request.
	Mean time.Duration
	// Median is the median lead time; zero below two pull requests (see
	// HasMedian).
	Median time.Duration
	// P90 is the 90th percentile of the lead times, nearest rank; zero below
	// minP90Gaps pull requests (see HasP90).
	P90 time.Duration
	// Cut counts the pull requests whose first commit time came from a cut
	// commit list, each lead time a lower bound (decision #299).
	Cut int
	// CreatedStandsIn counts the pull requests whose created time stood in
	// for the first commit time (decision #300).
	CreatedStandsIn int
	// Bots counts the pull requests merged in the DORA window that a bot
	// opened (history.ByBot, forsgren#345, step 2): never in the lead time.
	Bots int
	// NotReadable says collect was refused the pull request read of one of
	// the project's repositories (data/pulls_denied.csv, forsgren#337).
	NotReadable bool
}

// HasLeadTime says whether a pull request counted, so a mean to show.
func (m PRLeadTime) HasLeadTime() bool { return m.PullRequests > 0 }

// HasMedian says whether the median is shown: it needs two pull requests.
func (m PRLeadTime) HasMedian() bool { return m.PullRequests > 1 }

// HasP90 says whether the 90th percentile is shown: it needs minP90Gaps pull
// requests.
func (m PRLeadTime) HasP90() bool { return m.PullRequests >= minP90Gaps }

// PRLeadTimes returns the PR Lead Time of each project, in the
// order of projects, from the data's merged pull requests at the render time
// now, over its DORA window (30, 90 or 180 days).
func PRLeadTimes(projects []config.Project, data Data, now time.Time) []PRLeadTime {
	index := indexOf(projects)
	leads := make([][]float64, len(projects))
	out := make([]PRLeadTime, len(projects))
	for i, p := range projects {
		out[i].Project = p.Name
	}
	markNotReadable(out, index, data.PullsDenied)
	in := data.window()
	for _, p := range data.Pulls {
		i, ok := index.of(p.Repository)
		if !ok || !in.holds(p.MergedAt, now) {
			continue
		}
		leads[i] = out[i].add(p, leads[i])
	}
	for i := range out {
		out[i].spread(leads[i])
	}
	return out
}

// markNotReadable sets NotReadable on the project of each repository whose
// pull request read was refused (forsgren#337, step 2), compared ignoring
// case (decision #339); one refused repository makes its project's whole
// cell not readable, and a repository no project lists is left out.
func markNotReadable(out []PRLeadTime, index projectIndex, denied history.Reach) {
	for repository := range denied {
		if i, ok := index.of(repository); ok {
			out[i].NotReadable = true
		}
	}
}

// pullLeadOf is p's lead time: merged minus first commit time, the created time
// standing in when the commit list gave none, never below 0.
func pullLeadOf(p history.PullRequest) time.Duration {
	first := p.FirstCommitAt
	if p.CreatedStandsIn {
		first = p.CreatedAt
	}
	return max(p.MergedAt.Sub(first), 0)
}

// add counts p, a pull request of m's project merged in the window, and
// returns leads with its lead time in nanoseconds when a person opened it;
// any other is left out of the lead time, leads returned as they were.
func (m *PRLeadTime) add(p history.PullRequest, leads []float64) []float64 {
	if p.Bot != history.ByHuman {
		m.Bots += boolCount(p.Bot == history.ByBot)
		return leads
	}
	lead := pullLeadOf(p)
	m.note(p, lead)
	return append(leads, float64(lead))
}

// note counts p, whose lead time is lead, in m's counts.
func (m *PRLeadTime) note(p history.PullRequest, lead time.Duration) {
	m.PullRequests++
	m.Cut += boolCount(p.FirstCommitCut)
	m.CreatedStandsIn += boolCount(p.CreatedStandsIn)
}

// spread sets m's mean, median and 90th percentile of the lead times in
// nanoseconds, the last two while they are shown (forsgren#423).
func (m *PRLeadTime) spread(leads []float64) {
	if len(leads) == 0 {
		return
	}
	m.Mean = time.Duration(math.Round(meanOf(leads)))
	m.Median, m.P90 = medianAndP90(leads)
}

// boolCount is 1 for true, 0 for false.
func boolCount(b bool) int {
	if b {
		return 1
	}
	return 0
}
