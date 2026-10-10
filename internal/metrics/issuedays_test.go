package metrics

import (
	"slices"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// issueEvent is an event of issue 1 of repository at at.
func issueEvent(repository, event string, at time.Time) history.IssueEvent {
	return history.IssueEvent{Repository: repository, Issue: 1, Event: event, At: at}
}

// oct is the given day, hour, minute and second of October 2026, UTC.
func oct(d, h, m, s int) time.Time { return time.Date(2026, time.October, d, h, m, s, 0, time.UTC) }

// TestIssueDaysCountsNewIssuesPerUTCDayEndingYesterday (forsgren#76, step 7):
// with now on 3 October at noon and 3 days, the rows are 2 October, 1 October
// and 30 September, newest first. 23:59:59 and the next 00:00:00 land in
// different rows, both repositories count, a day without events is a zero
// row, and neither a reopened nor a closed event, nor anything today, is new.
func TestIssueDaysCountsNewIssuesPerUTCDayEndingYesterday(t *testing.T) {
	events := []history.IssueEvent{
		issueEvent("acme/app", "created", oct(1, 23, 59, 59)),
		issueEvent("acme/app", "created", oct(2, 0, 0, 0)),
		issueEvent("acme/cli", "created", oct(2, 5, 0, 0)),
		issueEvent("acme/app", "reopened", oct(2, 10, 0, 0)),
		issueEvent("acme/app", "closed", oct(2, 11, 0, 0)),
		issueEvent("acme/app", "created", oct(3, 0, 0, 0)),
		issueEvent("acme/app", "created", oct(3, 11, 0, 0)),
	}
	midnight := func(month time.Month, d int) time.Time { return time.Date(2026, month, d, 0, 0, 0, 0, time.UTC) }
	want := []IssueDay{
		{Date: midnight(time.October, 2), New: 2},
		{Date: midnight(time.October, 1), New: 1},
		{Date: midnight(time.September, 30), New: 0},
	}
	if got := IssueDays(events, now, 3); !slices.Equal(got, want) {
		t.Errorf("want the days\n%v\ngot\n%v", want, got)
	}
}

// closedAs is a closed event of acme/app at at, with reason.
func closedAs(reason string, at time.Time) history.IssueEvent {
	e := issueEvent("acme/app", "closed", at)
	e.Reason = reason
	return e
}

// TestIssueDaysCountsCompletedClosesPerUTCDay (forsgren#76, step 8): with now
// on 3 October at noon and 3 days, only a closed event with the reason
// completed is completed. 23:59:59 and the next 00:00:00 land in different
// rows, both repositories count, a close as not_planned, duplicate or with no
// reason is not completed, a reopened or created event is not, and a close
// today is out.
func TestIssueDaysCountsCompletedClosesPerUTCDay(t *testing.T) {
	other := closedAs("completed", oct(2, 6, 0, 0))
	other.Repository = "acme/cli"
	events := []history.IssueEvent{
		closedAs("completed", oct(1, 23, 59, 59)),
		closedAs("completed", oct(2, 0, 0, 0)),
		other,
		closedAs("not_planned", oct(2, 7, 0, 0)),
		closedAs("duplicate", oct(2, 8, 0, 0)),
		closedAs("", oct(2, 9, 0, 0)),
		issueEvent("acme/app", "reopened", oct(2, 10, 0, 0)),
		closedAs("completed", oct(3, 1, 0, 0)),
	}
	var got []int
	for _, d := range IssueDays(events, now, 3) {
		got = append(got, d.Completed)
	}
	if want := []int{2, 1, 0}; !slices.Equal(got, want) {
		t.Errorf("want Completed per day, newest first, %v, got %v", want, got)
	}
}
