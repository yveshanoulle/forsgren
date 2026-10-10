package metrics

import (
	"slices"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// issueEvent is an event of issue 1 of repository, at the given UTC time of
// September or October 2026.
func issueEvent(repository, event string, month time.Month, d, h, m, s int) history.IssueEvent {
	return history.IssueEvent{
		Repository: repository, Issue: 1, Event: event, At: time.Date(2026, month, d, h, m, s, 0, time.UTC),
	}
}

// TestIssueDaysCountsNewIssuesPerUTCDayEndingYesterday (forsgren#76, step 7):
// with now on 3 October at noon and 3 days, the rows are 2 October, 1 October
// and 30 September, newest first. 23:59:59 and the next 00:00:00 land in
// different rows, both repositories count, a day without events is a zero
// row, and neither a reopened nor a closed event, nor anything today, is new.
func TestIssueDaysCountsNewIssuesPerUTCDayEndingYesterday(t *testing.T) {
	events := []history.IssueEvent{
		issueEvent("acme/app", "created", time.October, 1, 23, 59, 59),
		issueEvent("acme/app", "created", time.October, 2, 0, 0, 0),
		issueEvent("acme/cli", "created", time.October, 2, 5, 0, 0),
		issueEvent("acme/app", "reopened", time.October, 2, 10, 0, 0),
		issueEvent("acme/app", "closed", time.October, 2, 11, 0, 0),
		issueEvent("acme/app", "created", time.October, 3, 0, 0, 0),
		issueEvent("acme/app", "created", time.October, 3, 11, 0, 0),
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
