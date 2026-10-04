package metrics

// The third number is failed deployment recovery time (forsgren#17), per
// configured project, from the stored deployments: DORA's "time it takes to
// recover from a deployment that fails and requires immediate
// intervention".
//
//   - a failure is a stored deployment whose state is failure: a GitHub
//     Deployment whose newest status is failure or error, or a run of a
//     `workflow=` rule that concluded failure. The web-hosting and TestFlight
//     recorders mark a deployment failed only once live was touched, so it
//     required intervention; a `workflow=` rule stores any failed run, also
//     one that failed before live was touched. Failure issues are change
//     failure rate's source (forsgren#18), not this one's;
//   - a failure is recovered by the next successful deployment of its
//     stream (history.Stream, collect's stream): the repository ignoring
//     case, the kind, the environment or workflow, and the task, while a
//     repository's releases are one stream;
//   - failures one after the other are one recovery, timed from the first
//     of them, when the service was first degraded, to the success;
//   - a deployment in another final state neither starts nor ends a run of
//     failures, and a deployment created after the render time is not
//     there yet;
//   - a recovery counts when its success was created in the last 30 days,
//     both ends included, the window of lead time;
//   - a run of failures with no success after it is not recovered yet: it
//     is counted and shown, whatever its age, but it has no time to put in
//     the median.
//
// The page shows the median, as for lead time, with its DORA band. The
// Quick Check's answers for failure recovery are word for word lead time's
// six, so a median recovery time is banded by LeadTimeBandOf.

import (
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// Recovery is one project's failed deployment recovery time at the render
// time.
type Recovery struct {
	Project string
	// Recoveries counts the runs of failures recovered in the last 30 days.
	Recoveries int
	// Median is their median recovery time; zero without recoveries.
	Median time.Duration
	// Band is the DORA band of Median (see LeadTimeBandOf); no band
	// without recoveries.
	Band LeadTimeBand
	// Unrecovered counts the runs of failures no success has followed yet,
	// at most one per stream.
	Unrecovered int
}

// RecoveryTimes returns the failed deployment recovery time of each
// project, in the order of projects, from the history records at the render
// time now.
func RecoveryTimes(projects []config.Project, records []history.Record, now time.Time) []Recovery {
	index := indexOf(projects)
	times := make([][]time.Duration, len(projects))
	out := make([]Recovery, len(projects))
	for s, deployments := range streamsOf(index, records, now) {
		i, _ := index.of(s.Repository)
		recovered, open := recoveriesOf(deployments, now)
		times[i] = append(times[i], recovered...)
		out[i].Unrecovered += open
	}
	for i, p := range projects {
		out[i].Project = p.Name
		out[i].over(times[i])
	}
	return out
}

// over sets r's count, median and band from its recovery times.
func (r *Recovery) over(times []time.Duration) {
	r.Recoveries = len(times)
	if r.Recoveries > 0 {
		r.Median = median(times)
		r.Band = LeadTimeBandOf(r.Median)
	}
}

// recoveriesOf walks one stream's deployments oldest first and returns the
// recovery times of the runs of failures recovered in the last 30 days, and
// 1 when the stream ends in a run of failures not recovered yet, else 0.
func recoveriesOf(deployments []history.Record, now time.Time) ([]time.Duration, int) {
	var out []time.Duration
	open := eachSuccess(deployments, func(s streamSuccess) {
		if s.recovered && last30.holds(s.at, now) {
			out = append(out, s.took)
		}
	})
	return out, open
}
