package metrics

// The second number is lead time for changes (forsgren#16, step 4), per
// configured project, from the commits `forsgren collect` stores in
// data/commits.csv:
//
//   - a commit's lead time runs from its author date to the creation time of
//     the successful deployment that shipped it (DORA's commit to running in
//     production; Yves's rulings 2 and 4);
//   - a commit counts when that deployment was created in the last 30 days,
//     both ends included, the window of deployment frequency's 30-day
//     count;
//   - a commit belongs to the project whose config lists its repository,
//     compared ignoring case, as for deployment frequency;
//   - each line counts: a commit shipped by two deployments (two tasks of
//     one repository) counts once for each;
//   - a commit authored after its deployment (a skewed clock, or an author
//     date set by hand) counts with a lead time of 0. It did ship, so
//     dropping it would lose a real change from the count, and a negative
//     time is impossible; 0 is the nearest possible value.
//
// The page shows the median, as DORA reports it: lead times are not
// normally distributed, and a few old commits would drag a mean far from the
// typical change. For an even count the median is the mean of the two
// middle lead times.

import (
	"slices"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// LeadTime is one project's lead time for changes at the render time.
type LeadTime struct {
	Project string
	// Commits counts the commits deployed in the last 30 days.
	Commits int
	// Median is their median lead time; zero without commits.
	Median time.Duration
	// Band is the DORA band of Median (see LeadTimeBandOf); no band
	// without commits.
	Band LeadTimeBand
}

// HasCommits says whether any commit was deployed in the window.
func (l LeadTime) HasCommits() bool { return l.Commits > 0 }

// BandText is the band with the median, the count and the period, "Less
// than one hour — median 17 minutes over 37 commits in the last 30 days"
// (forsgren#16, ruling 6), or "No lead time yet" without commits.
func (l LeadTime) BandText() string {
	if !l.HasCommits() {
		return "No lead time yet"
	}
	return bandText(l.Band, "median "+humanDuration(l.Median)+" over "+plural(l.Commits, "commit"), last30)
}

// LeadTimes returns the lead time for changes of each project, in the order
// of projects, from the stored commits at the render time now.
func LeadTimes(projects []config.Project, commits []history.Commit, now time.Time) []LeadTime {
	index := indexOf(projects)
	leads := make([][]time.Duration, len(projects))
	for _, c := range commits {
		i, ok := index.of(c.Repository)
		if ok && last30.holds(c.DeployedAt, now) {
			leads[i] = append(leads[i], leadTimeOf(c))
		}
	}
	out := make([]LeadTime, len(projects))
	for i, p := range projects {
		out[i] = leadTimeOver(p.Name, leads[i])
	}
	return out
}

// leadTimeOver is project's LeadTime over its commits' lead times.
func leadTimeOver(project string, leads []time.Duration) LeadTime {
	l := LeadTime{Project: project, Commits: len(leads)}
	if l.HasCommits() {
		l.Median = median(leads)
		l.Band = LeadTimeBandOf(l.Median)
	}
	return l
}

// leadTimeOf is c's lead time, from its author date to its deployment, and
// 0 when it was authored after the deployment.
func leadTimeOf(c history.Commit) time.Duration {
	return max(c.DeployedAt.Sub(c.AuthoredAt), 0)
}

// median is the middle of leads, which holds at least one, or the mean of
// the two middle ones when the count is even.
func median(leads []time.Duration) time.Duration {
	sorted := slices.Sorted(slices.Values(leads))
	mid := len(sorted) / 2
	if len(sorted)%2 == 1 {
		return sorted[mid]
	}
	return (sorted[mid-1] + sorted[mid]) / 2
}

// humanDuration writes d for the page: "less than a minute", whole minutes
// below an hour, hours and minutes below a day, days and hours above. Each
// part is cut down, never rounded up, so the text never reaches the next
// band's edge (23 hours 59 minutes, never 24 hours, is less than one day);
// a zero second part is left out.
func humanDuration(d time.Duration) string {
	switch {
	case d < time.Minute:
		return "less than a minute"
	case d < time.Hour:
		return plural(int(d/time.Minute), "minute")
	case d < day:
		return twoParts(int(d/time.Hour), "hour", int(d%time.Hour/time.Minute), "minute")
	default:
		return twoParts(int(d/day), "day", int(d%day/time.Hour), "hour")
	}
}

// twoParts is n units and then m smaller units, the latter left out at 0.
func twoParts(n int, unit string, m int, smaller string) string {
	if m == 0 {
		return plural(n, unit)
	}
	return plural(n, unit) + " " + plural(m, smaller)
}
