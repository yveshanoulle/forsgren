package metrics

// The third number is failed deployment recovery time (forsgren#17), per
// configured project, from the stored deployments: DORA's "time it takes to
// recover from a deployment that fails and requires immediate
// intervention".
//
//   - a failure is a stored deployment whose state is failure. The
//     recorders store one only once live was touched, so it required
//     intervention; failure issues are change failure rate's source
//     (forsgren#18), not this one's;
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
	"slices"
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

// BandText is the band with the median, the count and the period, "Less
// than one day — median 3 hours over 2 recoveries in the last 30 days",
// followed by "; 1 failure not recovered yet" when one is; "No recovery in
// the last 30 days; ..." when only an unrecovered one is; or "No failed
// deployments in the last 30 days" with neither.
func (r Recovery) BandText() string {
	text := "No failed deployments in " + last30.String()
	if r.Recoveries > 0 {
		text = bandText(r.Band, "median "+humanDuration(r.Median)+" over "+
			counted(r.Recoveries, "recovery", "recoveries"), last30)
	} else if r.Unrecovered > 0 {
		text = "No recovery in " + last30.String()
	}
	if r.Unrecovered > 0 {
		text += "; " + plural(r.Unrecovered, "failure") + " not recovered yet"
	}
	return text
}

// RecoveryTimes returns the failed deployment recovery time of each
// project, in the order of projects, from the history records at the render
// time now.
func RecoveryTimes(projects []config.Project, records []history.Record, now time.Time) []Recovery {
	index := indexOf(projects)
	streams := map[history.Stream][]history.Record{}
	for _, r := range records {
		if _, ok := index.of(r.Repository); ok && !r.CreatedAt.After(now) {
			streams[r.Stream()] = append(streams[r.Stream()], r)
		}
	}
	times := make([][]time.Duration, len(projects))
	out := make([]Recovery, len(projects))
	for s, deployments := range streams {
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

// recoveriesOf walks one stream's deployments oldest first (by created_at,
// then ID) and returns the recovery times of the runs of failures recovered
// in the last 30 days, and 1 when the stream ends in a run of failures not
// recovered yet, else 0.
func recoveriesOf(deployments []history.Record, now time.Time) ([]time.Duration, int) {
	slices.SortStableFunc(deployments, history.Chronological)
	var out []time.Duration
	var run outage
	for _, d := range deployments {
		switch d.State {
		case history.StateFailure:
			run.fail(d.CreatedAt)
		case history.StateSuccess:
			if took, ok := run.recover(d.CreatedAt); ok && last30.holds(d.CreatedAt, now) {
				out = append(out, took)
			}
		}
	}
	return out, run.open
}

// outage is a stream's current run of failures: open is 1 from its first
// failure, at since, until a success recovers it, else 0.
type outage struct {
	since time.Time
	open  int
}

// fail adds a failure at at to the run, starting it when none is open.
func (o *outage) fail(at time.Time) {
	if o.open == 0 {
		o.since, o.open = at, 1
	}
}

// recover ends the run with a success at at, and returns how long it took
// from its first failure; false when no run was open.
func (o *outage) recover(at time.Time) (time.Duration, bool) {
	was := o.open == 1
	o.open = 0
	return at.Sub(o.since), was
}
