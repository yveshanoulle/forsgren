package metrics

import (
	"reflect"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// at is the UTC time of a date and a clock time.
func at(year int, month time.Month, d, hour, min, sec int) time.Time {
	return time.Date(year, month, d, hour, min, sec, 0, time.UTC)
}

// labelsOf are the labels of periods, in their order.
func labelsOf(periods []Period) []string {
	labels := make([]string, len(periods))
	for i, p := range periods {
		labels[i] = p.Label
	}
	return labels
}

// TestPeriodsAreCalendarHalfYearsAndARollingNewest (forsgren#68): the columns
// are the complete calendar half-years (UTC) that start within history_days,
// oldest first, then the rolling last 180 days up to now; none under 180 days
// of history, and never more than the 1825 days history_days allows.
func TestPeriodsAreCalendarHalfYearsAndARollingNewest(t *testing.T) {
	const rolling = "Last 6 months"
	tests := []struct {
		name string
		now  time.Time
		days int
		want []string
	}{
		{"five years", at(2026, time.October, 15, 12, 0, 0), 1825, []string{"2022 H1", "2022 H2", "2023 H1", "2023 H2",
			"2024 H1", "2024 H2", "2025 H1", "2025 H2", "2026 H1", rolling}},
		{"a year", at(2026, time.October, 15, 12, 0, 0), 365, []string{"2026 H1", rolling}},
		{"more than the cap is the cap", at(2026, time.October, 15, 12, 0, 0), 2000, []string{"2022 H1", "2022 H2",
			"2023 H1", "2023 H2", "2024 H1", "2024 H2", "2025 H1", "2025 H2", "2026 H1", rolling}},
		{"exactly 180 days", at(2026, time.October, 15, 12, 0, 0), 180, []string{rolling}},
		{"under 180 days", at(2026, time.October, 15, 12, 0, 0), 179, nil},
		{"on January 1 the second half-year just ended", at(2026, time.January, 1, 0, 0, 0), 200,
			[]string{"2025 H2", rolling}},
		{"the last second of June, the first half-year is not complete", at(2026, time.June, 30, 23, 59, 59), 400,
			[]string{"2025 H2", rolling}},
		{"on July 1 the first half-year is complete", at(2026, time.July, 1, 0, 0, 0), 400,
			[]string{"2025 H2", "2026 H1", rolling}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := labelsOf(Periods(tt.now, tt.days))
			if !slices.Equal(got, tt.want) {
				t.Errorf("Periods(%s, %d) = %v, want %v", tt.now.Format(time.RFC3339), tt.days, got, tt.want)
			}
		})
	}
}

// TestPeriodsHaveTheirSpans (forsgren#68): a half-year runs from its first
// day to the first day of the next, a whole number of days; the rolling one
// from 180 days before now to now.
func TestPeriodsHaveTheirSpans(t *testing.T) {
	now := at(2026, time.October, 15, 12, 0, 0)
	want := []Period{
		{"2025 H2", at(2025, time.July, 1, 0, 0, 0), at(2026, time.January, 1, 0, 0, 0), false},
		{"2026 H1", at(2026, time.January, 1, 0, 0, 0), at(2026, time.July, 1, 0, 0, 0), false},
		{"Last 6 months", now.Add(-180 * 24 * time.Hour), now, true},
	}
	got := Periods(now, 500)
	if !slices.EqualFunc(got, want, func(a, b Period) bool {
		return a.Label == b.Label && a.Start.Equal(b.Start) && a.End.Equal(b.End) && a.Rolling == b.Rolling
	}) {
		t.Errorf("Periods(now, 500) = %+v, want %+v", got, want)
	}
}

// fullyRead is the reach of tableProjects' repositories when all their history
// was read, back to the epoch.
func fullyRead() history.Reach {
	reach := history.Reach{}
	for _, p := range tableProjects {
		for _, r := range p.Repositories {
			reach[strings.ToLower(r.Name)] = time.Unix(0, 0)
		}
	}
	return reach
}

// TestRollingPeriodEqualsTheNumbersAt180Days (forsgren#68): the newest column
// is the table's rows over the last 180 days, as dora_days: 180 gives them,
// for deployments, commits and failure issues up to six months old; what is
// older is not in it.
func TestRollingPeriodEqualsTheNumbersAt180Days(t *testing.T) {
	data := tableData()
	data.Records = append(data.Records,
		appDeployment(20, "deploy-api", history.StateFailure, 100*day),
		appDeployment(21, "deploy-api", history.StateSuccess, 100*day-time.Hour),
		appDeployment(22, "deploy-api", history.StateSuccess, 170*day),
		appDeployment(23, "deploy-api", history.StateSuccess, 200*day))
	data.Commits = append(data.Commits, shippedBy("acme/app", 21, 100*day-time.Hour, 3*day))
	data.Failures = append(data.Failures, history.Failure{Repository: "acme/app", Issue: 3, OpenedAt: now.Add(-150 * day)})
	rolling := Periods(now, 365)[1]
	data.Reach = fullyRead()
	got := PeriodRows(tableProjects, data, rolling)
	data.DoraDays = 180
	want := Rows(tableProjects, data, now)
	if !reflect.DeepEqual(got, want) {
		t.Errorf("rolling column = %+v, want the rows at 180 days %+v", got, want)
	}
}

// TestPastPeriodCountsStartButNotEndAndIgnoresLaterDeployments (forsgren#68):
// a calendar half-year is half-open, [Start, End): what is created at its
// start counts, what is created at its end or later is not seen at all, so a
// project whose first success came after the period has no deployment in it,
// and a commit deployed or a failure issue opened after it is not counted.
func TestPastPeriodCountsStartButNotEndAndIgnoresLaterDeployments(t *testing.T) {
	end := now.Add(-10 * day)
	past := Period{Label: "past", Start: end.Add(-184 * day), End: end}
	ok := history.StateSuccess
	data := Data{
		Records: []history.Record{
			appDeployment(1, "", ok, 10*day+185*day),
			appDeployment(2, "", ok, 10*day+184*day),
			appDeployment(3, "", ok, 10*day+time.Hour),
			appDeployment(4, "", ok, 10*day),
			appDeployment(5, "", ok, 5*day),
			released(withTask(deployed("acme/cli", ok, 5*day), 6, "v1.0")),
		},
		Commits: []history.Commit{
			shippedBy("acme/app", 3, 10*day+time.Hour, time.Hour),
			shippedBy("acme/app", 4, 10*day, time.Hour),
			shippedBy("acme/app", 5, 5*day, time.Hour),
		},
		Failures: []history.Failure{
			{Repository: "acme/app", Issue: 1, OpenedAt: end.Add(-time.Hour)},
			{Repository: "acme/app", Issue: 2, OpenedAt: end},
		},
	}
	data.Reach = fullyRead()
	rows := PeriodRows(tableProjects, data, past)
	shop, tools := rows[0], rows[len(rows)-1]
	if shop.Frequency.InWindow != 2 || !shop.Frequency.Latest.Equal(end.Add(-time.Hour)) {
		t.Errorf("Acme Shop deployments in the period = %d, latest %v, want 2 and %v", shop.Frequency.InWindow,
			shop.Frequency.Latest, end.Add(-time.Hour))
	}
	if shop.LeadTime.Commits != 1 || shop.ChangeFail.FailureIssues != 1 {
		t.Errorf("Acme Shop commits = %d, failure issues = %d, want 1 and 1", shop.LeadTime.Commits,
			shop.ChangeFail.FailureIssues)
	}
	if tools.Frequency.HasDeployments() {
		t.Errorf("Acme Tools deployed only after the period, but has deployments: latest %v", tools.Frequency.Latest)
	}
}

// TestHalfYearIsBandedAs180DaysWhateverItsLength (forsgren#68): every period
// is banded with the 180-day edges, and its own count is the count of the
// last 180 days: a 184-day half-year whose only deployments fall in its first
// four days deployed once per month or less, not never.
func TestHalfYearIsBandedAs180DaysWhateverItsLength(t *testing.T) {
	end := now.Add(-10 * day)
	period := Period{Label: "long", Start: end.Add(-184 * day), End: end}
	data := Data{Records: []history.Record{
		appDeployment(1, "", history.StateSuccess, 10*day+184*day-time.Hour),
		appDeployment(2, "", history.StateSuccess, 10*day+182*day),
		appDeployment(3, "", history.StateSuccess, 10*day+181*day),
	}}
	data.Reach = fullyRead()
	got := PeriodRows(tableProjects, data, period)[0].Frequency
	if got.InWindow != 3 || got.Band != MonthlyToSixMonthly {
		t.Errorf("3 deployments in the first days of a 184-day period: in window %d, band %v, want 3 and %v",
			got.InWindow, got.Band, MonthlyToSixMonthly)
	}
}

// TestRecoveryAndReworkInAPastPeriod (forsgren#68): recovery time and
// rework rate of a half-year that ended in the past. A failure from before
// the period recovered inside it counts, as a rework deployment; a failure
// still open at the end is not recovered, though a success followed at the
// end or later; a success while a failure issue was open is rework, one after
// it was closed is not.
func TestRecoveryAndReworkInAPastPeriod(t *testing.T) {
	end := now.Add(-10 * day)
	start := end.Add(-184 * day)
	ago := func(offset time.Duration) time.Duration { return now.Sub(start.Add(offset)) }
	ok, failure := history.StateSuccess, history.StateFailure
	data := Data{
		Records: []history.Record{
			appDeployment(1, "deploy-admin", failure, ago(-6*day)),
			appDeployment(2, "deploy-admin", ok, ago(day)),
			appDeployment(3, "deploy-api", ok, ago(5*day)),
			appDeployment(4, "deploy-api", failure, ago(183*day)),
			appDeployment(5, "deploy-api", ok, ago(184*day)),
			appDeployment(6, "deploy-api", ok, ago(190*day)),
			appDeployment(7, "deploy-web", ok, ago(20*day)),
			appDeployment(8, "deploy-web", ok, ago(50*day)),
		},
		Failures: []history.Failure{
			{Repository: "acme/app", Issue: 1, OpenedAt: start.Add(10 * day), ClosedAt: start.Add(30 * day)},
		},
	}
	data.Reach = fullyRead()
	shop := PeriodRows(tableProjects, data, Period{Label: "past", Start: start, End: end})[0]
	if r := shop.Recovery; r.Recoveries != 1 || r.Median != 7*day || r.Unrecovered != 1 {
		t.Errorf("recoveries = %d, median %v, unrecovered = %d, want 1, %v and 1", r.Recoveries, r.Median,
			r.Unrecovered, 7*day)
	}
	if r := shop.Rework; r.Deployments != 4 || r.Rework != 2 {
		t.Errorf("rework %d of %d successes, want 2 of 4", r.Rework, r.Deployments)
	}
}

// TestChangeFailAndLeadTimeInAPastPeriod (forsgren#68): change fail rate and
// lead time of a half-year that ended in the past. A failure issue counts when
// it was opened in the period, not before it, at its end or after it, and not
// when it is withdrawn; a commit counts by the date of its deployment, the
// start's but not the end's.
func TestChangeFailAndLeadTimeInAPastPeriod(t *testing.T) {
	end := now.Add(-10 * day)
	start := end.Add(-184 * day)
	ago := func(offset time.Duration) time.Duration { return now.Sub(start.Add(offset)) }
	opened := func(issue int64, offset time.Duration) history.Failure {
		return history.Failure{Repository: "acme/app", Issue: issue, OpenedAt: start.Add(offset)}
	}
	ok := history.StateSuccess
	data := Data{
		Records: []history.Record{
			appDeployment(1, "", ok, ago(day)), appDeployment(2, "", ok, ago(2*day)),
			appDeployment(3, "", ok, ago(3*day)), appDeployment(4, "", ok, ago(4*day)),
			appDeployment(5, "", history.StateFailure, ago(5*day)),
		},
		Commits: []history.Commit{
			shippedBy("acme/app", 1, ago(-day), day), shippedBy("acme/app", 2, ago(0), day),
			shippedBy("acme/app", 3, ago(10*day), 2*time.Hour), shippedBy("acme/app", 4, ago(100*day), 4*time.Hour),
			shippedBy("acme/app", 5, ago(184*day), 99*time.Hour), shippedBy("acme/app", 6, ago(190*day), time.Hour),
		},
		Failures: history.WithoutWithdrawn([]history.Failure{
			opened(1, -5*day), opened(2, 10*day), opened(3, 20*day), opened(4, 30*day),
			opened(5, 184*day), opened(6, 190*day),
		}, []history.Withdrawal{{Repository: "acme/app", Issue: 4, Withdrawn: true, Reason: history.ReasonLabelRemoved}}),
	}
	data.Reach = fullyRead()
	shop := PeriodRows(tableProjects, data, Period{Label: "past", Start: start, End: end})[0]
	if c := shop.ChangeFail; c.Deployments != 5 || c.FailureIssues != 2 || c.Failed != 2 {
		t.Errorf("change fail: %d deployments, %d failure issues, %d failed, want 5, 2 and 2", c.Deployments,
			c.FailureIssues, c.Failed)
	}
	if l := shop.LeadTime; l.Commits != 3 || l.Median != 4*time.Hour {
		t.Errorf("lead time: %d commits, median %v, want 3 and 4h", l.Commits, l.Median)
	}
}

// TestPeriodBeforeTheReachHasNoData (forsgren#68): history that was not read
// back to the start of a period is no data, not a quiet period: a row is
// unread when any repository it counts was read back only to a later date or
// has no reach noted, a project's total by its repositories, a repository's
// label by its own, a service's by its repository's.
func TestPeriodBeforeTheReachHasNoData(t *testing.T) {
	end := now.Add(-10 * day)
	period := Period{Label: "past", Start: end.Add(-184 * day), End: end}
	data := tableData()
	data.Reach = history.Reach{
		"acme/web": period.Start.Add(-day), "acme/app": period.Start.Add(day), "acme/extra": period.Start.Add(-10 * day),
	}
	unread := map[string]bool{}
	for _, row := range PeriodRows(tableProjects, data, period) {
		unread[row.Name] = row.Unread
	}
	want := map[string]bool{"Acme Shop": true, "ADMIN": true, "API": true, "IOS": true, "Website": false,
		"Acme Tools": true}
	if !reflect.DeepEqual(unread, want) {
		t.Errorf("unread rows = %v, want %v", unread, want)
	}
	data.Reach["acme/app"], data.Reach["acme/cli"] = period.Start, period.Start
	for _, row := range PeriodRows(tableProjects, data, period) {
		if row.Unread {
			t.Errorf("%s is unread with every repository read back to the start of the period", row.Name)
		}
	}
}
