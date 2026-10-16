package metrics

import (
	"slices"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// TestLeadMediansIsTheMedianOfTheClosesOfEachRow (forsgren#202, step 1): with
// now on 3 October at noon and 3 days, 2 October holds two closes, 36 h and
// 30 h after their creation, so its median is their mean, 33 h; 1 October holds
// one close of an issue created before the rows, 24 h; 30 September holds none,
// a zero LeadMedian.
func TestLeadMediansIsTheMedianOfTheClosesOfEachRow(t *testing.T) {
	events := []history.IssueEvent{
		appEvent(1, "created", oct(1, 0, 0, 0)),
		appEvent(2, "created", oct(1, 12, 0, 0)),
		appEvent(3, "created", time.Date(2026, time.September, 30, 6, 0, 0, 0, time.UTC)),
		closedIssue(1, oct(2, 12, 0, 0)),
		closedIssue(2, oct(2, 18, 0, 0)),
		closedIssue(3, oct(1, 6, 0, 0)),
	}
	today := utcDay(now)
	rowOf := func(at time.Time) (int, bool) { return dayRow(at, today, 3) }
	want := []LeadMedian{{Median: 33 * time.Hour, Count: 2}, {Median: 24 * time.Hour, Count: 1}, {}}
	if got := leadMedians(events, rowOf, 3); !slices.Equal(got, want) {
		t.Errorf("want the lead times\n%v\ngot\n%v", want, got)
	}
}

// closedIssue is a completed close of issue number of acme/app at at.
func closedIssue(number int64, at time.Time) history.IssueEvent {
	e := appEvent(number, "closed", at)
	e.Reason = history.ReasonCompleted
	return e
}

// TestLeadMediansCountsOnlyCompletedCloses (forsgren#202, step 2): on 2
// October a completed close 10 h after creation counts; a not planned, a
// duplicate, a close with no reason and one with a reason forsgren does not
// know, each of an issue created at the start of the day, are left out, as
// closedColumn leaves them out of Completed.
func TestLeadMediansCountsOnlyCompletedCloses(t *testing.T) {
	events := []history.IssueEvent{closedIssue(1, oct(2, 10, 0, 0))}
	events = append(events, appEvent(1, "created", oct(2, 0, 0, 0)))
	for i, reason := range []string{history.ReasonNotPlanned, history.ReasonDuplicate, "", "stale"} {
		number := int64(i + 2)
		events = append(events, appEvent(number, "created", oct(2, 0, 0, 0)), closedAs(reason, oct(2, 20, 0, 0)))
		events[len(events)-1].Issue = number
	}
	today := utcDay(now)
	rowOf := func(at time.Time) (int, bool) { return dayRow(at, today, 1) }
	want := []LeadMedian{{Median: 10 * time.Hour, Count: 1}}
	if got := leadMedians(events, rowOf, 1); !slices.Equal(got, want) {
		t.Errorf("want the lead times\n%v\ngot\n%v", want, got)
	}
}
