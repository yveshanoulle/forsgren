package metrics

// What failed deployment recovery time (forsgren#17) and deployment rework
// rate (forsgren#39) share: the stored deployments grouped by stream
// (history.Stream, collect's stream), and each stream walked oldest first
// with its current run of failures, so a success knows whether it
// recovered one.

import (
	"slices"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// streamsOf groups the records of listed repositories, not created after
// now, by stream.
func streamsOf(index projectIndex, records []history.Record, now time.Time) map[history.Stream][]history.Record {
	streams := map[history.Stream][]history.Record{}
	for _, r := range records {
		if _, ok := index.of(r.Repository); ok && !r.CreatedAt.After(now) {
			streams[r.Stream()] = append(streams[r.Stream()], r)
		}
	}
	return streams
}

// streamSuccess is one successful deployment of a stream: when it was
// created, whether it recovered a run of failures, and how long that run
// took from its first failure.
type streamSuccess struct {
	at        time.Time
	recovered bool
	took      time.Duration
}

// eachSuccess walks one stream's deployments oldest first (by created_at,
// then ID), calls each for every success, and returns 1 when the stream ends
// in a run of failures not recovered yet, else 0. A deployment in another
// final state neither starts nor ends a run.
func eachSuccess(deployments []history.Record, each func(streamSuccess)) int {
	slices.SortStableFunc(deployments, history.Chronological)
	var run outage
	for _, d := range deployments {
		switch d.State {
		case history.StateFailure:
			run.fail(d.CreatedAt)
		case history.StateSuccess:
			took, recovered := run.recover(d.CreatedAt)
			each(streamSuccess{at: d.CreatedAt, recovered: recovered, took: took})
		}
	}
	return run.open
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
