package metrics

// Mainline Lead Time (forsgren#256, step 1 of 3) is the second number of the
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
//   - the mean is the mean of the lead times and the deviation their sample
//     standard deviation (n-1); one pull request has a mean but no deviation;
//   - next to the mean, the reference of 24 hours (Yves's ruling on #256,
//     DORA's branches that live less than a day): WithinReference counts the
//     pull requests merged 24 hours or less after their first commit,
//     exactly 24 hours included, the same boundary everywhere (decision
//     #302), and WithinReferenceShare is their share in whole percent rounded
//     down. There is no pass or fail verdict;
//   - a project with a repository whose pull request read GitHub refused
//     (Data.PullsDenied, data/pulls_denied.csv, forsgren#337) is NotReadable
//     as a whole, whatever was read of its other repositories.
//
// The result is per project; the TBD page's column (step 2) writes it with
// Cell, mainlineleadcell.go.

import (
	"math"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// leadReference is Mainline Lead Time's reference: a pull request merged this
// long or less after its first commit counts as within it (forsgren#256).
const leadReference = 24 * time.Hour

// MainlineLeadTime is one project's Mainline Lead Time at the render time.
type MainlineLeadTime struct {
	Project string
	// PullRequests counts the pull requests merged in the DORA window.
	PullRequests int
	// Mean is the mean lead time; zero without a pull request.
	Mean time.Duration
	// Deviation is the sample standard deviation of the lead times; zero
	// below two pull requests (see HasDeviation).
	Deviation time.Duration
	// WithinReference counts the pull requests merged leadReference or less
	// after their first commit.
	WithinReference int
	// Cut counts the pull requests whose first commit time came from a cut
	// commit list, each lead time a lower bound (decision #299).
	Cut int
	// CreatedStandsIn counts the pull requests whose created time stood in
	// for the first commit time (decision #300).
	CreatedStandsIn int
	// NotReadable says collect was refused the pull request read of one of
	// the project's repositories (data/pulls_denied.csv, forsgren#337).
	NotReadable bool
}

// HasLeadTime says whether a pull request counted, so a mean to show.
func (m MainlineLeadTime) HasLeadTime() bool { return m.PullRequests > 0 }

// HasDeviation says whether the sample standard deviation exists: it needs
// two pull requests.
func (m MainlineLeadTime) HasDeviation() bool { return m.PullRequests > 1 }

// WithinReferenceShare is the share of the counted pull requests merged
// within the reference, in whole percent rounded down, so 100 only when every
// one was; 0 without a pull request.
func (m MainlineLeadTime) WithinReferenceShare() int {
	if !m.HasLeadTime() {
		return 0
	}
	return m.WithinReference * 100 / m.PullRequests
}

// MainlineLeadTimes returns the Mainline Lead Time of each project, in the
// order of projects, from the data's merged pull requests at the render time
// now, over its DORA window (30, 90 or 180 days).
func MainlineLeadTimes(projects []config.Project, data Data, now time.Time) []MainlineLeadTime {
	index := indexOf(projects)
	leads := make([][]float64, len(projects))
	out := make([]MainlineLeadTime, len(projects))
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
		lead := pullLeadOf(p)
		leads[i] = append(leads[i], float64(lead))
		out[i].note(p, lead)
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
func markNotReadable(out []MainlineLeadTime, index projectIndex, denied history.Reach) {
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

// note counts p, whose lead time is lead, in m's counts.
func (m *MainlineLeadTime) note(p history.PullRequest, lead time.Duration) {
	m.PullRequests++
	m.WithinReference += boolCount(lead <= leadReference)
	m.Cut += boolCount(p.FirstCommitCut)
	m.CreatedStandsIn += boolCount(p.CreatedStandsIn)
}

// spread sets m's mean and, from two, sample deviation of the lead times in
// nanoseconds.
func (m *MainlineLeadTime) spread(leads []float64) {
	if len(leads) == 0 {
		return
	}
	mean := meanOf(leads)
	m.Mean = time.Duration(math.Round(mean))
	if m.HasDeviation() {
		m.Deviation = time.Duration(math.Round(sampleDeviation(leads, mean)))
	}
}

// boolCount is 1 for true, 0 for false.
func boolCount(b bool) int {
	if b {
		return 1
	}
	return 0
}
