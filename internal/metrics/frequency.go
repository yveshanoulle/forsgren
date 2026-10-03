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
	"fmt"
	"strings"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// day is one window day: 24 hours, counted back from the render time in UTC.
const day = 24 * time.Hour

// Frequency is one project's deployment frequency at the render time.
type Frequency struct {
	Project string
	// Last7 and Last30 count the successful deployments created in the
	// last 7 and 30 days: at or after now minus 7 (30) times 24 hours, and
	// not after now. A deployment exactly 7 days old is in the 7-day count.
	Last7, Last30 int
	// Latest is the creation time of the project's newest successful
	// deployment; zero when it has none.
	Latest time.Time
	// Band is the DORA performance band of Last30 (see BandOf).
	Band Band
}

// HasDeployments says whether the project has any successful deployment
// recorded, at any time.
func (f Frequency) HasDeployments() bool { return !f.Latest.IsZero() }

// LatestDate is Latest as a UTC calendar date, 2026-10-01.
func (f Frequency) LatestDate() string { return f.Latest.UTC().Format(time.DateOnly) }

// BandText is the band together with the count and the period it comes
// from, "Daily to weekly — 12 production deployments in the last 30 days"
// (Yves's ruling on forsgren#12): the band describes throughput over the
// period, not regularity, and the count makes a burst visible.
func (f Frequency) BandText() string {
	noun := "production deployments"
	if f.Last30 == 1 {
		noun = "production deployment"
	}
	return fmt.Sprintf("%s — %d %s in the last 30 days", f.Band, f.Last30, noun)
}

// DeploymentFrequency returns the deployment frequency of each project, in
// the order of projects, from the history records at the render time now.
func DeploymentFrequency(projects []config.Project, records []history.Record, now time.Time) []Frequency {
	owner := owners(projects)
	out := make([]Frequency, len(projects))
	for i, p := range projects {
		out[i].Project = p.Name
	}
	for _, r := range records {
		i, ok := owner[strings.ToLower(r.Repository)]
		if ok && r.State == history.StateSuccess {
			out[i].add(r.CreatedAt, now)
		}
	}
	for i := range out {
		out[i].Band = BandOf(out[i].Last30)
	}
	return out
}

// owners maps each configured repository, lower-case, to its project's index.
func owners(projects []config.Project) map[string]int {
	owner := map[string]int{}
	for i, p := range projects {
		for _, r := range p.Repositories {
			owner[strings.ToLower(r.Name)] = i
		}
	}
	return owner
}

// add counts one successful deployment created at, seen at now.
func (f *Frequency) add(at, now time.Time) {
	if at.After(f.Latest) {
		f.Latest = at
	}
	f.Last7 += within(at, now, 7)
	f.Last30 += within(at, now, 30)
}

// within is 1 when at lies in the last days days before now, both ends
// included, else 0.
func within(at, now time.Time, days int) int {
	start := now.Add(-time.Duration(days) * day)
	if at.Before(start) || at.After(now) {
		return 0
	}
	return 1
}
