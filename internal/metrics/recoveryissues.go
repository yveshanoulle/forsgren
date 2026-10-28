package metrics

// Failure issues in failed deployment recovery time (forsgren#53): each
// issue is a recovery from its failure start to its closing, unless it is
// the same incident as a run of failed deployments of its repository, which
// recovery time already counts.

import (
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// span is the time of an incident: from start to end, end being zero while
// it is not over.
type span struct{ start, end time.Time }

// overlaps says whether s and o share a moment, an end included; an
// incident not over yet reaches the render time and beyond.
func (s span) overlaps(o span) bool {
	return !s.startsAfter(o.end) && !o.startsAfter(s.end)
}

// startsAfter says whether s starts after end, an end that is zero never
// being reached.
func (s span) startsAfter(end time.Time) bool { return !end.IsZero() && s.start.After(end) }

// duration is how long the incident lasted, never negative.
func (s span) duration() time.Duration { return max(s.end.Sub(s.start), 0) }

// issueSpan is the issue's time: from its `failure-start:` line, or from its
// opening when it has none, to its closing.
func issueSpan(f history.Failure) span {
	start := f.FailureStart
	if start.IsZero() {
		start = f.OpenedAt
	}
	return span{start, f.ClosedAt}
}

// issueRecoveries returns the recovery times of the issues of one
// repository closed in the window w, and how many open ones there are, each
// left out when its time overlaps one of the repository's runs of failed
// deployments; an issue opened after the render time is not there yet.
func issueRecoveries(issues []history.Failure, runs []span, w window, now time.Time) ([]time.Duration, int) {
	var times []time.Duration
	open := 0
	for _, f := range issues {
		s := issueSpan(f)
		if f.OpenedAt.After(now) || overlapsAny(s, runs) {
			continue
		}
		switch {
		case f.ClosedAt.IsZero():
			open++
		case w.holds(f.ClosedAt, now):
			times = append(times, s.duration())
		}
	}
	return times, open
}

// overlapsAny says whether s overlaps one of runs.
func overlapsAny(s span, runs []span) bool {
	for _, r := range runs {
		if s.overlaps(r) {
			return true
		}
	}
	return false
}
