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
	// Last7 and Last30 count the successful deployments created in the
	// last 7 and 30 days: at or after now minus 7 (30) times 24 hours, and
	// not after now. A deployment exactly 7 days old is in the 7-day count.
	Last7, Last30 int
	// Last180 counts them over the last 180 days the same way, for the two
	// slowest bands (forsgren#16, step 6).
	Last180 int
	// Latest is the creation time of the project's newest successful
	// deployment; zero when it has none.
	Latest time.Time
	// Band is the DORA band of Last30, or of Last180 when Last30 is 0 (see
	// BandOf); a project younger than 30 days scales Last30 to 30 days
	// first (see bandOfAge, forsgren#69).
	Band Band
}

// HasDeployments says whether the project has any successful deployment
// recorded, at any time.
func (f Frequency) HasDeployments() bool { return !f.Latest.IsZero() }

// DeploymentFrequency returns the deployment frequency of each project, in
// the order of projects, from the history records at the render time now.
func DeploymentFrequency(projects []config.Project, records []history.Record, now time.Time) []Frequency {
	index := indexOf(projects)
	out := make([]Frequency, len(projects))
	for i, p := range projects {
		out[i].Project = p.Name
	}
	firsts := make([]time.Time, len(projects))
	for _, r := range records {
		i, ok := index.of(r.Repository)
		if ok && r.State == history.StateSuccess {
			out[i].add(r.CreatedAt, now)
			firsts[i] = earlier(firsts[i], r.CreatedAt)
		}
	}
	for i := range out {
		out[i].Band = bandOfAge(out[i].Last30, out[i].Last180, firsts[i], now)
	}
	return out
}

// add counts one successful deployment created at, seen at now.
func (f *Frequency) add(at, now time.Time) {
	if at.After(f.Latest) {
		f.Latest = at
	}
	f.Last7 += last7.count(at, now)
	f.Last30 += last30.count(at, now)
	f.Last180 += last180.count(at, now)
}
