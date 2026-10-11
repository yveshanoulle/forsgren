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
// row, and neither a reopened nor a closed event (this one has no reason, so it
// is Other, decision #107), nor anything today, is new.
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
		{Date: midnight(time.October, 2), New: 2, Other: 1, Total: 3},
		{Date: midnight(time.October, 1), New: 1, Total: 1},
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

// closesWithReason are the closes of reason that every close column test
// uses: 1 October 23:59:59 and the next 00:00:00 land in different rows, a
// second repository counts on the second day, and a close today is out.
func closesWithReason(reason string) []history.IssueEvent {
	other := closedAs(reason, oct(2, 6, 0, 0))
	other.Repository = "acme/cli"
	return []history.IssueEvent{
		closedAs(reason, oct(1, 23, 59, 59)), closedAs(reason, oct(2, 0, 0, 0)), other, closedAs(reason, oct(3, 1, 0, 0)),
	}
}

// TestIssueDaysCountsCompletedClosesPerUTCDay (forsgren#76, step 8): with now
// on 3 October at noon and 3 days, only a closed event with the reason
// completed is completed. 23:59:59 and the next 00:00:00 land in different
// rows, both repositories count, a close as not_planned, duplicate or with no
// reason is not completed, a reopened or created event is not, and a close
// today is out.
func TestIssueDaysCountsCompletedClosesPerUTCDay(t *testing.T) {
	events := append(closesWithReason("completed"),
		closedAs("not_planned", oct(2, 7, 0, 0)),
		closedAs("duplicate", oct(2, 8, 0, 0)),
		closedAs("", oct(2, 9, 0, 0)),
		issueEvent("acme/app", "reopened", oct(2, 10, 0, 0)),
	)
	var got []int
	for _, d := range IssueDays(events, now, 3) {
		got = append(got, d.Completed)
	}
	if want := []int{2, 1, 0}; !slices.Equal(got, want) {
		t.Errorf("want Completed per day, newest first, %v, got %v", want, got)
	}
}

// closeCounts are the close columns of one day.
type closeCounts struct{ completed, notPlanned, duplicate, other int }

// checkColumn fails t unless column of each day of IssueDays over events, with
// now on 3 October at noon and 3 days, newest first, is want.
func checkColumn[T comparable](t *testing.T, events []history.IssueEvent, column func(IssueDay) T, want []T) {
	t.Helper()
	var got []T
	for _, d := range IssueDays(events, now, 3) {
		got = append(got, column(d))
	}
	if !slices.Equal(got, want) {
		t.Errorf("want per day, newest first, %v, got %v", want, got)
	}
}

// checkCloseCounts fails t unless the close columns of each day are want.
func checkCloseCounts(t *testing.T, events []history.IssueEvent, want []closeCounts) {
	t.Helper()
	checkColumn(t, events, func(d IssueDay) closeCounts {
		return closeCounts{d.Completed, d.NotPlanned, d.Duplicate, d.Other}
	}, want)
}

// TestIssueDaysCountsNotPlannedClosesPerUTCDay (forsgren#76, v0.6.1): a close
// with the reason not_planned is counted in NotPlanned on its day, in no other
// column, while a completed close counts as Completed only.
func TestIssueDaysCountsNotPlannedClosesPerUTCDay(t *testing.T) {
	events := append(closesWithReason("not_planned"), closedAs("completed", oct(2, 8, 0, 0)))
	checkCloseCounts(t, events, []closeCounts{{1, 2, 0, 0}, {0, 1, 0, 0}, {}})
}

// TestIssueDaysCountsDuplicateClosesPerUTCDay (forsgren#76, v0.6.1): a close
// with the reason duplicate is counted in Duplicate on its day, in no other
// column, while a not planned close counts as NotPlanned only.
func TestIssueDaysCountsDuplicateClosesPerUTCDay(t *testing.T) {
	events := append(closesWithReason("duplicate"), closedAs("not_planned", oct(2, 9, 0, 0)))
	checkCloseCounts(t, events, []closeCounts{{0, 1, 2, 0}, {0, 0, 1, 0}, {}})
}

// TestIssueDaysCountsClosesWithoutAKnownReasonAsOther (forsgren#76, v0.6.1,
// decision #107): a close with no reason (an old issue) or a reason forsgren
// does not know is counted in Other on its day, in no other column, so every
// close lands in exactly one column.
func TestIssueDaysCountsClosesWithoutAKnownReasonAsOther(t *testing.T) {
	for _, reason := range []string{"", "something_new"} {
		t.Run("reason "+reason, func(t *testing.T) {
			events := append(closesWithReason(reason), closedAs("duplicate", oct(2, 9, 0, 0)))
			checkCloseCounts(t, events, []closeCounts{{0, 0, 1, 2}, {0, 0, 0, 1}, {}})
		})
	}
}

// sep30 is 10:00 on 30 September 2026, UTC, the oldest row's day.
var sep30 = time.Date(2026, time.September, 30, 10, 0, 0, 0, time.UTC)

// checkTotals fails t unless the Total of each day is want.
func checkTotals(t *testing.T, events []history.IssueEvent, want []int) {
	t.Helper()
	checkColumn(t, events, func(d IssueDay) int { return d.Total }, want)
}

// TestIssueDaysTotalCountsTheIssuesCreatedUpToTheEndOfTheDay (forsgren#76,
// v0.6.2): the Total of a day is how many issues were created by its last
// second, all repositories together; an issue created today is in no row.
func TestIssueDaysTotalCountsTheIssuesCreatedUpToTheEndOfTheDay(t *testing.T) {
	checkTotals(t, []history.IssueEvent{
		issueEvent("acme/app", "created", sep30),
		issueEvent("acme/cli", "created", oct(1, 8, 0, 0)),
		issueEvent("acme/app", "created", oct(2, 9, 0, 0)),
		issueEvent("acme/app", "created", oct(3, 1, 0, 0)),
	}, []int{3, 2, 1})
}

// TestIssueDaysTotalDropsFromTheDayAnIssueIsClosed (forsgren#76, v0.6.2): an
// issue created and then closed, whatever the reason, is open until the day of
// its close and no longer from then on.
func TestIssueDaysTotalDropsFromTheDayAnIssueIsClosed(t *testing.T) {
	checkTotals(t, []history.IssueEvent{
		issueEvent("acme/app", "created", sep30),
		issueEvent("acme/cli", "created", oct(1, 8, 0, 0)),
		closedAs("not_planned", oct(2, 9, 0, 0)),
	}, []int{1, 2, 1})
}

// TestIssueDaysTotalRisesAgainFromTheDayAnIssueIsReopened (forsgren#76,
// v0.6.2): an issue closed and then reopened is open again from the day of the
// reopen on, and counts in the Total once more.
func TestIssueDaysTotalRisesAgainFromTheDayAnIssueIsReopened(t *testing.T) {
	checkTotals(t, []history.IssueEvent{
		issueEvent("acme/app", "created", sep30),
		closedAs("completed", oct(1, 9, 0, 0)),
		issueEvent("acme/app", "reopened", oct(2, 9, 0, 0)),
	}, []int{1, 0, 1})
}
