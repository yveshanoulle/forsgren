// Package metrics computes the DORA numbers the page shows, from the
// history `forsgren collect` stores (forsgren#12, step 7). Its functions are
// pure: the render time comes in as an argument, never from the clock.
//
// The first number is deployment frequency, per configured project:
//
//   - a deployment is a stored record whose state is success; a failure or
//     other record does not count (Yves's ruling on forsgren#12);
//   - a record belongs to the project whose config lists its repository
//     (compared ignoring case, as the config compares names), so a renamed
//     project keeps its history and a repository no project lists any more
//     is left out;
//   - every success counts on its own, also when one repository deploys
//     several services (API, admin, iOS); the split per service is
//     forsgren#11.
package metrics

import (
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// Frequency is one project's deployment frequency at the render time.
type Frequency struct {
	Project string
	// Last7 and InWindow count the successful deployments created in the
	// last 7 days and in the DORA window (dora_days: 30, 90 or 180 days,
	// forsgren#178): at or after now minus 7 (the window's) times 24 hours,
	// and not after now. A deployment exactly 7 days old is in the 7-day
	// count.
	Last7, InWindow int
	// Last180 counts them over the last 180 days the same way, for the two
	// slowest bands (forsgren#16, step 6).
	Last180 int
	// WeekendInWindow counts the InWindow successes created on a Saturday or
	// a Sunday, UTC (forsgren#115).
	WeekendInWindow int
	// Weekend180 counts the Last180 successes created on a Saturday or a
	// Sunday, UTC (forsgren#115).
	Weekend180 int
	// Latest is the creation time of the project's newest successful
	// deployment; zero when it has none.
	Latest time.Time
	// Band is the DORA band of InWindow, or of Last180 when InWindow is 0
	// (see BandOf); a project younger than the window scales InWindow to the
	// window first (see scaledToAge, forsgren#69).
	Band Band
}

// HasDeployments says whether the project has any successful deployment
// recorded, at any time.
func (f Frequency) HasDeployments() bool { return !f.Latest.IsZero() }

// DeploymentFrequency returns the deployment frequency of each project, in
// the order of projects, from the data's history records at the render time
// now, over its DORA window (30, 90 or 180 days, forsgren#178) and with its
// working day.
func DeploymentFrequency(projects []config.Project, data Data, now time.Time) []Frequency {
	days := data.days()
	index := indexOf(projects)
	out := make([]Frequency, len(projects))
	for i, p := range projects {
		out[i].Project = p.Name
	}
	firsts := make([]time.Time, len(projects))
	for _, r := range data.Records {
		i, ok := index.of(r.Repository)
		if ok && r.State == history.StateSuccess {
			out[i].add(r.CreatedAt, now, window(days))
			firsts[i] = earlier(firsts[i], r.CreatedAt)
		}
	}
	for i := range out {
		out[i].band(data, firsts[i], now)
	}
	return out
}

// band sets f's Band from its counts, first being its first successful
// deployment: over the data's banding days, and for a data that sets them the
// 180-day count is the window's own (forsgren#68).
func (f *Frequency) band(data Data, first, now time.Time) {
	days := data.bandedDays()
	if data.BandDays != 0 {
		f.Last180 = f.InWindow
	}
	f.Band = BandOf(scaledToAge(f.InWindow, days, first, now), f.Last180, data.WorkingHours, days)
}

// add counts one successful deployment created at, seen at now, InWindow and
// WeekendInWindow over the DORA window w (forsgren#178).
func (f *Frequency) add(at, now time.Time, w window) {
	if at.After(f.Latest) {
		f.Latest = at
	}
	f.Last7 += last7.count(at, now)
	f.InWindow += w.count(at, now)
	f.Last180 += last180.count(at, now)
	if isWeekend(at) {
		f.WeekendInWindow += w.count(at, now)
		f.Weekend180 += last180.count(at, now)
	}
}

// isWeekend says whether t falls on a Saturday or a Sunday, UTC. The days
// are fixed until forsgren#72 makes them configurable.
func isWeekend(t time.Time) bool {
	day := t.UTC().Weekday()
	return day == time.Saturday || day == time.Sunday
}
