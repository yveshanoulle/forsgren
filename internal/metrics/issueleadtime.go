package metrics

// The lead time of issues (forsgren#202): per period, the median time from the
// creation of an issue to its close, over the issues closed in that period.

import (
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

// leadMedians is, for each of n rows, the LeadMedian of the closes rowOf gives
// that row (the index of an event time's row, as periodRows uses it), over the
// completed closes only, each measured from the issue's created event.
func leadMedians(events []history.IssueEvent, rowOf func(time.Time) (int, bool), n int) []LeadMedian {
	created := createdAt(events)
	leads := make([][]time.Duration, n)
	for _, e := range events {
		i, ok := rowOf(e.At)
		if completedClose(e) && ok {
			leads[i] = append(leads[i], e.At.Sub(created[issueKeyOf(e)]))
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
