package metrics

// The lead time of issues (forsgren#202): per period, the median time from the
// creation of an issue to its close, over the issues closed in that period.

import (
	"slices"
	"strings"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// LeadMedian is the median lead time of the issues closed in one period, and
// how many closes it is over; Count 0 means no issue was closed in the period
// and Median is 0.
type LeadMedian struct {
	Median time.Duration
	Count  int
}

// Cell is the median in the short form of the lead time for changes
// (shortDuration), "—" when no issue was closed in the period, the dash the
// issues table shows for an empty value (OpenShare).
func (l LeadMedian) Cell() string {
	if l.Count == 0 {
		return "—"
	}
	return shortDuration(l.Median)
}

// leadMedians is, for each of n rows, the LeadMedian of the closes rowOf gives
// that row (the index of an event time's row, as periodRows uses it), over the
// completed closes only, each measured from the issue's created event; a close
// with no created event is left out.
func leadMedians(events []history.IssueEvent, rowOf func(time.Time) (int, bool), n int) []LeadMedian {
	created := createdAt(events)
	leads := make([][]time.Duration, n)
	for _, e := range events {
		i, ok := rowOf(e.At)
		lead, measured := leadOf(e, created)
		if ok && measured {
			leads[i] = append(leads[i], lead)
		}
	}
	return medianEach(leads)
}

// medianEach is the LeadMedian of each of leads, the zero one for no lead.
func medianEach(leads [][]time.Duration) []LeadMedian {
	medians := make([]LeadMedian, len(leads))
	for i, l := range leads {
		if len(l) > 0 {
			medians[i] = LeadMedian{Median: median(l), Count: len(l)}
		}
	}
	return medians
}

// setLeadTimes sets the LeadTime of each of rows from the closes of events that
// rowOf places on it, and its BugsLeadTime from those of the bug issues.
func setLeadTimes(rows []IssueDay, events []history.IssueEvent, rowOf func(time.Time) (int, bool)) {
	for i, lead := range leadMedians(events, rowOf, len(rows)) {
		rows[i].LeadTime = lead
	}
	for i, lead := range leadMedians(bugEvents(events), rowOf, len(rows)) {
		rows[i].BugsLeadTime = lead
	}
}

// bugEvents are the events of events that belong to an issue carrying the bug
// label, the flag bugDelta reads.
func bugEvents(events []history.IssueEvent) []history.IssueEvent {
	return slices.DeleteFunc(slices.Clone(events), func(e history.IssueEvent) bool { return !e.Bug })
}

// leadOf is the lead time of e, from the creation of its issue (created) to
// e; false when e is not a completed close or its issue has no created event,
// which leaves it without a lead time.
func leadOf(e history.IssueEvent, created map[issueKey]time.Time) (time.Duration, bool) {
	at, ok := created[issueKeyOf(e)]
	if !ok || !completedClose(e) {
		return 0, false
	}
	return e.At.Sub(at), true
}

// completedClose is whether e is a close that closedColumn counts as Completed,
// the one classification of a close's reason.
func completedClose(e history.IssueEvent) bool {
	if e.Event != history.EventClosed {
		return false
	}
	var d IssueDay
	return d.closedColumn(e.Reason) == &d.Completed
}

// issueKey names an issue: its repository, lower case, and its number.
type issueKey struct {
	repository string
	issue      int64
}

// issueKeyOf is the issueKey of e, the repository compared ignoring case as
// the issues format keys it.
func issueKeyOf(e history.IssueEvent) issueKey {
	return issueKey{strings.ToLower(e.Repository), e.Issue}
}

// createdAt is when each issue was created, by its created event.
func createdAt(events []history.IssueEvent) map[issueKey]time.Time {
	created := make(map[issueKey]time.Time)
	for _, e := range events {
		if e.Event == history.EventCreated {
			created[issueKeyOf(e)] = e.At
		}
	}
	return created
}
