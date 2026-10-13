package metrics

import (
	"cmp"
	"slices"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// issueEvent is an event of issue 1 of repository at at.
func issueEvent(repository, event string, at time.Time) history.IssueEvent {
	return history.IssueEvent{Repository: repository, Issue: 1, Event: event, At: at}
}

// appEvent is an event of issue number of acme/app at at.
func appEvent(number int64, event string, at time.Time) history.IssueEvent {
	return history.IssueEvent{Repository: "acme/app", Issue: number, Event: event, At: at}
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
		{Date: midnight(time.October, 2), New: 2, Other: 1, Open: 3, OpenChange: 2, Total: 3, Active: true},
		{Date: midnight(time.October, 1), New: 1, Open: 1, OpenChange: 1, Total: 1, Active: true},
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

// columnOf is column of each day of IssueDays over events, with now on 3
// October at noon and 3 days, newest first.
func columnOf[T any](events []history.IssueEvent, column func(IssueDay) T) []T {
	var got []T
	for _, d := range IssueDays(events, now, 3) {
		got = append(got, column(d))
	}
	return got
}

// checkColumn fails t unless columnOf(events, column) is want.
func checkColumn[T comparable](t *testing.T, events []history.IssueEvent, column func(IssueDay) T, want []T) {
	t.Helper()
	if got := columnOf(events, column); !slices.Equal(got, want) {
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

// openOf is the Open column of d.
func openOf(d IssueDay) int { return d.Open }

// active is whether d is Active (forsgren#108).
func active(d IssueDay) bool { return d.Active }

// checkOpen fails t unless the Open of each day is want.
func checkOpen(t *testing.T, events []history.IssueEvent, want []int) {
	t.Helper()
	checkColumn(t, events, openOf, want)
}

// TestIssueDaysOpenCountsTheIssuesCreatedWhileNoneIsClosed (forsgren#76,
// v0.6.2): with no close, the Open of a day is how many issues were created by
// its last second, all repositories together; an issue created today is in no
// row.
func TestIssueDaysOpenCountsTheIssuesCreatedWhileNoneIsClosed(t *testing.T) {
	checkOpen(t, []history.IssueEvent{
		issueEvent("acme/app", "created", sep30),
		issueEvent("acme/cli", "created", oct(1, 8, 0, 0)),
		issueEvent("acme/app", "created", oct(2, 9, 0, 0)),
		issueEvent("acme/app", "created", oct(3, 1, 0, 0)),
	}, []int{3, 2, 1})
}

// TestIssueDaysOpenDropsFromTheDayAnIssueIsClosed (forsgren#76, v0.6.2): an
// issue created and then closed, whatever the reason, is open until the day of
// its close and no longer from then on.
func TestIssueDaysOpenDropsFromTheDayAnIssueIsClosed(t *testing.T) {
	checkOpen(t, []history.IssueEvent{
		issueEvent("acme/app", "created", sep30),
		issueEvent("acme/cli", "created", oct(1, 8, 0, 0)),
		closedAs("not_planned", oct(2, 9, 0, 0)),
	}, []int{1, 2, 1})
}

// TestIssueDaysOpenRisesAgainFromTheDayAnIssueIsReopened (forsgren#76,
// v0.6.2): an issue closed and then reopened is open again from the day of the
// reopen on, and counts in the Open once more.
func TestIssueDaysOpenRisesAgainFromTheDayAnIssueIsReopened(t *testing.T) {
	checkOpen(t, []history.IssueEvent{
		issueEvent("acme/app", "created", sep30),
		closedAs("completed", oct(1, 9, 0, 0)),
		issueEvent("acme/app", "reopened", oct(2, 9, 0, 0)),
	}, []int{1, 0, 1})
}

// TestIssueDaysOpenStartsFromTheIssuesOpenBeforeTheWindow (forsgren#76,
// v0.6.2): the issues created before the oldest row's day and not closed
// before it are open on every row, so the Open starts from them, not from 0.
func TestIssueDaysOpenStartsFromTheIssuesOpenBeforeTheWindow(t *testing.T) {
	checkOpen(t, []history.IssueEvent{
		issueEvent("acme/app", "created", sep30.AddDate(0, 0, -10)),
		issueEvent("acme/cli", "created", sep30.AddDate(0, 0, -5)),
		closedAs("completed", sep30.AddDate(0, 0, -2)),
		issueEvent("acme/app", "created", oct(1, 8, 0, 0)),
	}, []int{2, 2, 1})
}

// TestIssueDaysOpenIgnoresAnEventItDoesNotKnow: an event that is not created,
// closed or reopened, before the window or in it, leaves the Open as it was.
func TestIssueDaysOpenIgnoresAnEventItDoesNotKnow(t *testing.T) {
	checkOpen(t, []history.IssueEvent{
		issueEvent("acme/app", "labeled", sep30.AddDate(0, 0, -3)),
		issueEvent("acme/app", "created", sep30),
		issueEvent("acme/app", "labeled", oct(1, 8, 0, 0)),
	}, []int{1, 1, 1})
}

// closeOfIssue is a close of acme/app's issue number at at, completed.
func closeOfIssue(number int64, at time.Time) history.IssueEvent {
	e := closedAs("completed", at)
	e.Issue = number
	return e
}

// TestIssueDaysOpenCountsACloseOfAnIssueItNeverSawCreated (forsgren#122,
// overruling #120): a close counts -1 whether or not its issue has a created
// event in the list, before the window or in it, so the Open goes below the
// open issues it knows.
func TestIssueDaysOpenCountsACloseOfAnIssueItNeverSawCreated(t *testing.T) {
	checkOpen(t, []history.IssueEvent{
		closeOfIssue(7, sep30.AddDate(0, 0, -3)),
		issueEvent("acme/app", "created", sep30),
		closeOfIssue(8, oct(1, 8, 0, 0)),
	}, []int{-1, -1, 0})
}

// reopenOfIssue is a reopen of acme/app's issue number at at.
func reopenOfIssue(number int64, at time.Time) history.IssueEvent {
	return appEvent(number, "reopened", at)
}

// TestIssueDaysOpenCountsAReopenOfAnIssueItNeverSawCreated (forsgren#122,
// overruling #113): a reopen counts +1 whether or not its issue has a created
// event in the list, so closed, reopened, closed of such an issue is -1, +1,
// -1 on the Open.
func TestIssueDaysOpenCountsAReopenOfAnIssueItNeverSawCreated(t *testing.T) {
	checkOpen(t, []history.IssueEvent{
		closeOfIssue(7, sep30.AddDate(0, 0, -3)),
		issueEvent("acme/app", "created", sep30),
		reopenOfIssue(7, oct(1, 8, 0, 0)),
		closeOfIssue(7, oct(2, 8, 0, 0)),
	}, []int{0, 1, 0})
}

// TestIssueDaysOpenDoesNotDependOnTheOrderOfTheLines (forsgren#76, v0.6.2):
// issues.csv can hold an event after a later one (a backfill appends older
// events at the end), so a close can come before its own created line, even
// within one second. Reordering the events must not change any Open: the
// list in file order and the same events sorted by time give the same days.
func TestIssueDaysOpenDoesNotDependOnTheOrderOfTheLines(t *testing.T) {
	fileOrder := []history.IssueEvent{
		closedAs("completed", oct(1, 8, 0, 0)),
		issueEvent("acme/app", "created", oct(1, 8, 0, 0)),
		issueEvent("acme/cli", "created", sep30),
	}
	sorted := slices.Clone(fileOrder)
	slices.SortStableFunc(sorted, func(a, b history.IssueEvent) int {
		order := []string{"created", "closed", "reopened"}
		return cmp.Or(a.At.Compare(b.At), slices.Index(order, a.Event)-slices.Index(order, b.Event))
	})
	checkOpen(t, sorted, columnOf(fileOrder, openOf))
}

// TestIssueDaysMarksADayWithoutEventsInactive (forsgren#108, step 1): with
// now on 3 October at noon and 3 days, only 1 October has an event, so 2
// October and 30 September, with nothing new, closed or reopened, are not
// Active, and 1 October is.
func TestIssueDaysMarksADayWithoutEventsInactive(t *testing.T) {
	events := []history.IssueEvent{issueEvent("acme/app", "created", oct(1, 8, 0, 0))}
	checkColumn(t, events, active, []bool{false, true, false})
}

// TestIssueDaysKeepsADayWithOnlyAReopenActive (forsgren#108, step 3): a
// reopen changes the Open, so a day with nothing new and no close but a
// reopen is Active (rule 1). Only 2 October has the reopen; 1 October has the
// issue created, 30 September nothing.
func TestIssueDaysKeepsADayWithOnlyAReopenActive(t *testing.T) {
	events := []history.IssueEvent{
		issueEvent("acme/app", "created", oct(1, 8, 0, 0)),
		issueEvent("acme/app", "reopened", oct(2, 8, 0, 0)),
	}
	checkColumn(t, events, active, []bool{true, true, false})
}

// totalOf is the Total column of d.
func totalOf(d IssueDay) int { return d.Total }

// TestIssueDaysTotalCountsTheIssuesCreatedUpToTheEndOfTheDay (forsgren#134,
// step 2): the Total of a day is the created events up to its last second,
// open or closed, before the window or in it, all repositories together, so it
// never drops at a close and a reopen adds none; a close of an issue whose
// created event is not in the list adds none either, and nothing today counts.
// The Open column of the same events is 2, 2, 1.
func TestIssueDaysTotalCountsTheIssuesCreatedUpToTheEndOfTheDay(t *testing.T) {
	events := []history.IssueEvent{
		issueEvent("acme/app", "created", sep30.AddDate(0, 0, -10)),
		closeOfIssue(7, sep30.AddDate(0, 0, -5)),
		appEvent(2, "created", sep30),
		issueEvent("acme/cli", "created", oct(1, 8, 0, 0)),
		closedAs("completed", oct(2, 8, 0, 0)),
		reopenOfIssue(2, oct(2, 9, 0, 0)),
		appEvent(3, "created", oct(3, 1, 0, 0)),
	}
	checkOpen(t, events, []int{2, 2, 1})
	checkColumn(t, events, totalOf, []int{3, 3, 2})
}

// TestIssueDayOpenShareIsOpenOutOfTotalInWholePercentRoundedDown (forsgren#134,
// step 4): 2 open out of 3 created is 66%, not 67%, the rounding of change fail
// rate; all open is 100%.
func TestIssueDayOpenShareIsOpenOutOfTotalInWholePercentRoundedDown(t *testing.T) {
	for _, c := range []struct {
		open, total int
		want        string
	}{{2, 3, "66%"}, {3, 3, "100%"}} {
		if got := (IssueDay{Open: c.open, Total: c.total}).OpenShare(); got != c.want {
			t.Errorf("Open %d of Total %d: want %q, got %q", c.open, c.total, c.want, got)
		}
	}
}

// TestIssueDayOpenShareIsADashWhenNoIssueWasCreated (forsgren#134, step 5): with
// a Total of 0 there is nothing to take a share of, so the share is the dash the
// page shows for a missing number, whatever Open is.
func TestIssueDayOpenShareIsADashWhenNoIssueWasCreated(t *testing.T) {
	for _, open := range []int{0, -1} {
		if got := (IssueDay{Open: open}).OpenShare(); got != "—" {
			t.Errorf("Open %d of Total 0: want %q, got %q", open, "—", got)
		}
	}
}

// openBugsOf is the OpenBugs of d.
func openBugsOf(d IssueDay) int { return d.OpenBugs }

// bugEvent is e of an issue that carries the bug label.
func bugEvent(e history.IssueEvent) history.IssueEvent {
	e.Bug = true
	return e
}

// TestIssueDaysOpenBugsCountsTheOpenIssuesThatAreBugs (forsgren#126): the
// OpenBugs of a day is its Open counted over the events of bug issues alone:
// +1 for a created or reopened event, -1 for a closed one, an issue that is
// not a bug adds nothing, and the Open column is the same as without bugs.
func TestIssueDaysOpenBugsCountsTheOpenIssuesThatAreBugs(t *testing.T) {
	events := []history.IssueEvent{
		bugEvent(appEvent(2, "created", sep30)),
		bugEvent(appEvent(4, "created", oct(1, 8, 0, 0))),
		appEvent(5, "created", oct(1, 9, 0, 0)),
		bugEvent(closeOfIssue(2, oct(2, 8, 0, 0))),
	}
	checkColumn(t, events, openBugsOf, []int{1, 2, 1})
	checkOpen(t, events, []int{2, 3, 1})
}

// TestIssueDaysOpenTrendIsUpByTheIssuesAddedWhenTheOpenRose (forsgren#126,
// forsgren#114): a day whose Open is higher than the day before's has the
// trend Up and, as its change, how many more issues are open.
func TestIssueDaysOpenTrendIsUpByTheIssuesAddedWhenTheOpenRose(t *testing.T) {
	days := IssueDays([]history.IssueEvent{
		appEvent(1, "created", sep30),
		appEvent(2, "created", oct(1, 8, 0, 0)),
		appEvent(3, "created", oct(1, 9, 0, 0)),
	}, now, 3)
	if oct1 := days[1]; oct1.OpenTrend() != TrendUp || oct1.OpenChange != 2 {
		t.Errorf("want 1 October Up by 2, got trend %v by %d", oct1.OpenTrend(), oct1.OpenChange)
	}
}

// TestIssueDaysOpenTrendIsDownByTheIssuesClosedWhenTheOpenFell (forsgren#126,
// forsgren#114): a day whose Open is lower than the day before's has the trend
// Down and, as its change, minus how many fewer issues are open. Proven by
// mutation.
func TestIssueDaysOpenTrendIsDownByTheIssuesClosedWhenTheOpenFell(t *testing.T) {
	days := IssueDays([]history.IssueEvent{
		appEvent(1, "created", sep30),
		appEvent(2, "created", sep30),
		appEvent(3, "created", sep30),
		closeOfIssue(1, oct(1, 8, 0, 0)),
		closeOfIssue(2, oct(1, 9, 0, 0)),
	}, now, 3)
	if oct1 := days[1]; oct1.OpenTrend() != TrendDown || oct1.OpenChange != -2 {
		t.Errorf("want 1 October Down by 2, got trend %v by %d", oct1.OpenTrend(), oct1.OpenChange)
	}
}

// TestIssueDaysOpenTrendIsFlatWhenTheOpenDidNotChange (forsgren#126,
// forsgren#114): a day whose Open equals the day before's has the trend Flat
// and the change 0, also a day that nets to zero: one issue created and one
// closed. Proven by mutation, because Flat is the zero value.
func TestIssueDaysOpenTrendIsFlatWhenTheOpenDidNotChange(t *testing.T) {
	days := IssueDays([]history.IssueEvent{
		appEvent(1, "created", sep30),
		appEvent(2, "created", oct(1, 8, 0, 0)),
		closeOfIssue(1, oct(1, 9, 0, 0)),
	}, now, 3)
	for _, day := range days[:2] {
		if day.OpenTrend() != TrendFlat || day.OpenChange != 0 {
			t.Errorf("want %v Flat by 0, got trend %v by %d", day.Date, day.OpenTrend(), day.OpenChange)
		}
	}
}

// TestIssueDaysOpenTrendOfTheOldestRowIsAgainstTheDayBeforeTheRange
// (forsgren#126, forsgren#114): the oldest row is compared with the issues open
// at the end of the day before it, though that day is outside the rows. 30
// September has 2 open, one of them created before the rows and one on the day,
// so it is Up by 1, not by 2. Proven by mutation.
func TestIssueDaysOpenTrendOfTheOldestRowIsAgainstTheDayBeforeTheRange(t *testing.T) {
	days := IssueDays([]history.IssueEvent{
		appEvent(1, "created", sep30.AddDate(0, 0, -10)),
		appEvent(2, "created", sep30),
	}, now, 3)
	oldest := days[2]
	got := openMove{oldest.Open, oldest.OpenTrend(), oldest.OpenChange}
	if want := (openMove{2, TrendUp, 1}); got != want {
		t.Errorf("want 30 September with %+v, got %+v", want, got)
	}
}

// openMove is how many issues a day has open, and which way and by how much
// that moved from the day before.
type openMove struct {
	open   int
	trend  Trend
	change int
}
