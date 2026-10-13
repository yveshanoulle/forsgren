package metrics

import (
	"slices"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// TestIssueRowsListDaysThenWeeksThenMonths (forsgren#89, step 11): with now
// on Wednesday 14 October 2026 and an event in each period, the rows are
// Tuesday 13 and Monday 12, then week 41 (Monday 5 October) and week 40
// (Monday 28 September), then September and August, each with its kind.
func TestIssueRowsListDaysThenWeeksThenMonths(t *testing.T) {
	at := func(month time.Month, d int) time.Time {
		return time.Date(2026, month, d, 12, 0, 0, 0, time.UTC)
	}
	var events []history.IssueEvent
	for i, when := range []time.Time{
		at(time.October, 13), at(time.October, 6), at(time.September, 29),
		at(time.September, 10), at(time.August, 20),
	} {
		events = append(events, appEvent(int64(i+1), "created", when))
	}
	type row struct {
		kind  string
		month time.Month
		day   int
	}
	want := []row{
		{KindDay, time.October, 13}, {KindDay, time.October, 12},
		{KindWeek, time.October, 5}, {KindWeek, time.September, 28},
		{KindMonth, time.September, 1}, {KindMonth, time.August, 1},
	}
	var got []row
	for _, r := range IssueRows(events, at(time.October, 14)) {
		got = append(got, row{r.Kind, r.Date.Month(), r.Date.Day()})
	}
	if !slices.Equal(got, want) {
		t.Errorf("want the rows\n%v\ngot\n%v", want, got)
	}
}

// TestIssueRowsShowSixDaysOnASunday (forsgren#89, step 12): on Sunday 18
// October 2026 the current week has six days before today, Saturday 17 back to
// Monday 12, and they come before the weeks.
func TestIssueRowsShowSixDaysOnASunday(t *testing.T) {
	created := time.Date(2026, time.October, 6, 12, 0, 0, 0, time.UTC)
	events := []history.IssueEvent{issueEvent("acme/app", "created", created)}
	var days []int
	for _, r := range IssueRows(events, time.Date(2026, time.October, 18, 12, 0, 0, 0, time.UTC)) {
		if r.Kind == KindDay {
			days = append(days, r.Date.Day())
		}
	}
	if want := []int{17, 16, 15, 14, 13, 12}; !slices.Equal(days, want) {
		t.Errorf("want the days %v, got %v", want, days)
	}
}

// TestIssueRowsEndWithYearRowsAfterTheCurrentYearsMonths (forsgren#125, step
// 6): with now on Wednesday 14 October 2026 and events back to 2024, the
// month rows are September back to January 2026 and one year row each for
// 2025 and 2024 follows, newest first. On Tuesday 5 January 2027 the current
// year has no complete month, so the year rows follow the weeks directly.
func TestIssueRowsEndWithYearRowsAfterTheCurrentYearsMonths(t *testing.T) {
	at := func(year int, month time.Month, d int) time.Time {
		return time.Date(year, month, d, 12, 0, 0, 0, time.UTC)
	}
	type row struct {
		kind  string
		year  int
		month time.Month
	}
	periods := func(events []history.IssueEvent, now time.Time) []row {
		var got []row
		for _, r := range IssueRows(events, now) {
			if r.Kind == KindMonth || r.Kind == KindYear {
				got = append(got, row{r.Kind, r.Date.Year(), r.Date.Month()})
			}
		}
		return got
	}
	events := []history.IssueEvent{
		appEvent(1, "created", at(2024, time.March, 3)),
		appEvent(2, "created", at(2025, time.November, 3)),
		appEvent(3, "created", at(2026, time.February, 3)),
		appEvent(4, "created", at(2026, time.September, 10)),
	}
	want := []row{
		{KindMonth, 2026, time.September}, {KindMonth, 2026, time.August}, {KindMonth, 2026, time.July},
		{KindMonth, 2026, time.June}, {KindMonth, 2026, time.May}, {KindMonth, 2026, time.April},
		{KindMonth, 2026, time.March}, {KindMonth, 2026, time.February}, {KindMonth, 2026, time.January},
		{KindYear, 2025, time.January}, {KindYear, 2024, time.January},
	}
	if got := periods(events, at(2026, time.October, 14)); !slices.Equal(got, want) {
		t.Errorf("want the periods\n%v\ngot\n%v", want, got)
	}
	january := []history.IssueEvent{
		appEvent(1, "created", at(2025, time.June, 3)),
		appEvent(2, "created", at(2026, time.December, 10)),
	}
	wantJanuary := []row{{KindYear, 2026, time.January}, {KindYear, 2025, time.January}}
	if got := periods(january, at(2027, time.January, 5)); !slices.Equal(got, wantJanuary) {
		t.Errorf("want the periods\n%v\ngot\n%v", wantJanuary, got)
	}
}
