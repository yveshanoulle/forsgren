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
//     one that failed before live was touched;
//   - a failure issue (the `failure` label, forsgren#18) is a recovery of
//     its own (forsgren#53), timed from its `failure-start:` line, or from
//     its opening when it has none, to its closing; an open issue is a
//     recovery not completed yet, as an open run of failures is. Nothing
//     stored links an issue to the deployment it is about, so, as change fail
//     rate counts the larger of the two, an issue counts once with a run:
//     one whose time overlaps the time of a run of failures of its
//     repository, from the first failure to the success or to now, both
//     ends included, is that incident and is left out, the run's
//     recovery counting alone. An issue overlapping no run counts as its
//     own recovery. A failed deployment recovery time of a service or a
//     rule row reads the issues whose service is its label, as change fail
//     rate does. Rework rate reads the issues as it did and does not change;
//   - a failure is recovered by the next successful deployment of its
//     stream (history.Stream, collect's stream): the repository ignoring
//     case, the kind, the environment or workflow, and the task, while a
//     repository's releases are one stream;
//   - failures one after the other are one recovery, timed from the first
//     of them, when the service was first degraded, to the success;
//   - a deployment in another final state neither starts nor ends a run of
//     failures, and a deployment created after the render time is not
//     there yet;
//   - a recovery counts when its success (an issue: its closing) was created
//     in the DORA window
//     (dora_days: the last 30, 90 or 180 days, forsgren#178), both ends
//     included, the window of lead time;
//   - a run of failures with no success after it, or an open issue left out
//     as above, is not recovered yet: it is counted and shown, whatever its
//     age, but it has no time to put in the median.
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
	// Recoveries counts the runs of failures recovered in the DORA window.
	Recoveries int
	// Median is their median recovery time; zero without recoveries.
	Median time.Duration
	// Band is the DORA band of Median (see LeadTimeBandOf); no band
	// without recoveries.
	Band LeadTimeBand
	// Unrecovered counts the runs of failures no success has followed yet,
	// at most one per stream, and the open failure issues that overlap no
	// run (forsgren#53).
	Unrecovered int
}

// RecoveryTimes returns the failed deployment recovery time of each
// project, in the order of projects, from the data's history records at the
// render time now, over its DORA window (30, 90 or 180 days): a recovery
// counts when its success was created in the window (forsgren#178). A run not
// recovered yet is counted whatever its age.
func RecoveryTimes(projects []config.Project, data Data, now time.Time) []Recovery {
	index := indexOf(projects)
	times := make([][]time.Duration, len(projects))
	out := make([]Recovery, len(projects))
	runs := map[string][]span{}
	for s, deployments := range streamsOf(index, data.Records, now) {
		i, _ := index.of(s.Repository)
		found := recoveriesOf(deployments, data.window(), now)
		times[i] = append(times[i], found.times...)
		out[i].Unrecovered += found.open
		runs[s.Repository] = append(runs[s.Repository], found.runs...)
	}
	for repository, issues := range issuesByRepository(data.Failures) {
		if i, ok := index.of(repository); ok {
			recovered, open := issueRecoveries(issues, runs[repository], data.window(), now)
			times[i] = append(times[i], recovered...)
			out[i].Unrecovered += open
		}
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

// streamRecoveries is what one stream's walk found: the recovery times of
// the runs recovered in the window, 1 in open when it ends in a run not
// recovered yet, and the time of every run, in the window or not.
type streamRecoveries struct {
	times []time.Duration
	open  int
	runs  []span
}

// recoveriesOf walks one stream's deployments oldest first and returns its
// recoveries in the window w.
func recoveriesOf(deployments []history.Record, w window, now time.Time) streamRecoveries {
	var out streamRecoveries
	run := eachSuccess(deployments, func(s streamSuccess) {
		if !s.recovered {
			return
		}
		out.runs = append(out.runs, span{s.at.Add(-s.took), s.at})
		if w.holds(s.at, now) {
			out.times = append(out.times, s.took)
		}
	})
	out.open = run.open
	if run.open == 1 {
		out.runs = append(out.runs, span{start: run.since})
	}
	return out
}
