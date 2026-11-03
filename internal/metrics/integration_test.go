package metrics

import (
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// The integration measures (forsgren#622, step 1). integrationNow is a
// Wednesday; its 30-day window starts on Monday 2026-09-07 12:00 UTC, so it
// spans the dates 7 September to 7 October, 23 of them working days.
var integrationNow = time.Date(2026, 10, 7, 12, 0, 0, 0, time.UTC)

const windowWorkingDays = 23

// onMain is one commit by login that reached main at at (a push of its own).
type onMain struct {
	login string
	at    time.Time
}

func atHour(month time.Month, d, hour int) time.Time {
	return time.Date(2026, month, d, hour, 0, 0, 0, time.UTC)
}

// integrationData stores each commit of commits as a first-parent commit of
// its own push to acme/app.
func integrationData(commits []onMain) Data {
	var data Data
	for i, c := range commits {
		after := fmt.Sprintf("tip%d", i)
		data.Pushes = append(data.Pushes, history.Push{Repository: "acme/app", PushedAt: c.at, Before: "base",
			After: after, Kind: history.PushKindPush, Bot: history.ByHuman, Commits: 1})
		data.PushCommits = append(data.PushCommits, history.PushCommit{Repository: "acme/app", After: after,
			SHA: fmt.Sprintf("sha%d", i), Author: c.login, AuthoredAt: c.at, FirstParent: true, Parents: 1})
	}
	return data
}

func integrationOf(commits []onMain, groups [][]string) Integration {
	return IntegrationOf(projects, integrationData(commits), integrationNow, groups)[0]
}

func perDay(commits int) float64 { return float64(commits) / windowWorkingDays }

// one is the spread of a single value: only the mean and the count are shown.
func one(mean float64) CountSpread { return CountSpread{Count: 1, Mean: mean} }

// firstWeekdays are n commits by login, one on each of the first n working
// days of the window, at 13:00.
func firstWeekdays(login string, n int) []onMain {
	var out []onMain
	for d := atHour(time.September, 7, 13); len(out) < n; d = d.AddDate(0, 0, 1) {
		if d.Weekday() != time.Saturday && d.Weekday() != time.Sunday {
			out = append(out, onMain{login, d})
		}
	}
	return out
}

func TestIntegrationOfOneDeveloperTable(t *testing.T) {
	cases := []struct {
		name    string
		commits []onMain
		groups  [][]string
		want    Integration
	}{
		{"weekend skipped: Friday to Monday is one working day, Monday to Wednesday two",
			[]onMain{{"a", atHour(time.October, 2, 10)}, {"a", atHour(time.October, 5, 10)}}, nil,
			Integration{Active: 1, PerDay: one(perDay(2)), Freshness: one(2), Gap: one(1), GapLongest: 1}},
		{"a Saturday commit counts as a commit, not as a working day",
			[]onMain{{"a", atHour(time.October, 3, 10)}, {"a", atHour(time.October, 7, 9)}}, nil,
			Integration{Active: 1, PerDay: one(perDay(2)), Freshness: one(0), Gap: one(3), GapLongest: 3}},
		{"bots, the placeholder login and no login are left out",
			[]onMain{{"a", atHour(time.October, 7, 9)}, {"dependabot[bot]", atHour(time.October, 7, 9)},
				{"Invalid-Email-Address", atHour(time.October, 7, 9)}, {"", atHour(time.October, 7, 9)}}, nil,
			Integration{Active: 1, PerDay: one(perDay(1)), Freshness: one(0)}},
		{"a same_developer group and a login in another case are one developer",
			[]onMain{{"Alice", atHour(time.October, 5, 9)}, {"alice-work", atHour(time.October, 6, 9)},
				{"ALICE", atHour(time.October, 7, 9)}}, [][]string{{"alice", "alice-work"}},
			Integration{Active: 1, PerDay: one(perDay(3)), Freshness: one(0), Gap: one(1), GapLongest: 1}},
		{"one commit has no gap",
			[]onMain{{"a", atHour(time.October, 6, 9)}}, nil,
			Integration{Active: 1, PerDay: one(perDay(1)), Freshness: one(1)}},
		{"window edges: the start and the render time are in, a second before the start is out",
			[]onMain{{"in", atHour(time.September, 7, 12)}, {"in", integrationNow},
				{"out", atHour(time.September, 7, 12).Add(-time.Second)}}, nil,
			Integration{Active: 1, PerDay: one(perDay(2)), Freshness: one(0), Gap: one(22), GapLongest: 22}},
		{"19 of 23 working days is at least 4 of every 5",
			firstWeekdays("a", 19), nil,
			Integration{Active: 1, Regular: 1, PerDay: one(perDay(19)), Freshness: one(4), Gap: one(1), GapLongest: 1}},
		{"18 of 23 working days is not",
			firstWeekdays("a", 18), nil,
			Integration{Active: 1, PerDay: one(perDay(18)), Freshness: one(5), Gap: one(1), GapLongest: 1}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			c.want.Project, c.want.WorkingDays = "Acme Shop", windowWorkingDays
			if got := integrationOf(c.commits, c.groups); got != c.want {
				t.Errorf("want %+v, got %+v", c.want, got)
			}
		})
	}
}

func TestIntegrationOfTakesTheMedianAndTheLongestOverDevelopers(t *testing.T) {
	got := integrationOf([]onMain{{"a", atHour(time.October, 7, 9)}, {"b", atHour(time.October, 5, 9)},
		{"b", atHour(time.October, 7, 9)}, {"c", atHour(time.October, 1, 9)}, {"c", atHour(time.October, 7, 9)}}, nil)
	got.PerDay = CountSpread{}
	want := Integration{Project: "Acme Shop", Active: 3, WorkingDays: windowWorkingDays,
		Freshness: CountSpread{Count: 3}, Gap: CountSpread{Count: 2, Mean: 3, Median: 3, Deviation: got.Gap.Deviation},
		GapLongest: 4}
	if got != want {
		t.Errorf("want %+v, got %+v", want, got)
	}
}

func TestIntegrationOfAProjectWithoutCommitsIsEmpty(t *testing.T) {
	got := IntegrationOf(projects, Data{}, integrationNow, nil)[0]
	if want := (Integration{Project: "Acme Shop", WorkingDays: windowWorkingDays}); got != want {
		t.Errorf("want %+v, got %+v", want, got)
	}
}

func TestIntegrationHoldsNoLogin(t *testing.T) {
	got := integrationOf([]onMain{{"secretlogin", atHour(time.October, 5, 9)},
		{"other-secret", atHour(time.October, 6, 9)}}, [][]string{{"secretlogin", "group-secret"}})
	if text := fmt.Sprintf("%+v", got); strings.Contains(text, "secret") {
		t.Errorf("a login is in the result: %s", text)
	}
}
