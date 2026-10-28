package metrics

import (
	"reflect"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// at is the UTC time written in RFC 3339, such as 2026-10-15T12:00:00Z.
func at(rfc3339 string) time.Time {
	t, err := time.Parse(time.RFC3339, rfc3339)
	if err != nil {
		panic(err)
	}
	return t
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
		{"five years", at("2026-10-15T12:00:00Z"), 1825, []string{"2022 H1", "2022 H2", "2023 H1", "2023 H2",
			"2024 H1", "2024 H2", "2025 H1", "2025 H2", "2026 H1", rolling}},
		{"a year", at("2026-10-15T12:00:00Z"), 365, []string{"2026 H1", rolling}},
		{"more than the cap is the cap", at("2026-10-15T12:00:00Z"), 2000, []string{"2022 H1", "2022 H2",
			"2023 H1", "2023 H2", "2024 H1", "2024 H2", "2025 H1", "2025 H2", "2026 H1", rolling}},
		{"exactly 180 days", at("2026-10-15T12:00:00Z"), 180, []string{rolling}},
		{"under 180 days", at("2026-10-15T12:00:00Z"), 179, nil},
		{"on January 1 the second half-year just ended", at("2026-01-01T00:00:00Z"), 200,
			[]string{"2025 H2", rolling}},
		{"the last second of June, the first half-year is not complete", at("2026-06-30T23:59:59Z"), 400,
			[]string{"2025 H2", rolling}},
		{"on July 1 the first half-year is complete", at("2026-07-01T00:00:00Z"), 400,
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
	now := at("2026-10-15T12:00:00Z")
	want := []Period{
		{"2025 H2", at("2025-07-01T00:00:00Z"), at("2026-01-01T00:00:00Z"), false},
		{"2026 H1", at("2026-01-01T00:00:00Z"), at("2026-07-01T00:00:00Z"), false},
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
func fullyRead() history.Reach { return readBackTo(time.Unix(0, 0)) }

// readBackTo is the reach of tableProjects' repositories when all were read
// back to at.
func readBackTo(at time.Time) history.Reach {
	reach := history.Reach{}
	for _, p := range tableProjects {
		for _, r := range p.Repositories {
			reach[strings.ToLower(r.Name)] = at
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
// it was closed is not. The issue, 20 days from opening to closing and
// overlapping no run of failures, is a recovery too (forsgren#53).
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
	r := shop.Recovery
	if got, want := [3]any{r.Recoveries, r.Median, r.Unrecovered}, [3]any{2, 13*day + 12*time.Hour, 1}; got != want {
		t.Errorf("recoveries, median, unrecovered = %v, want %v", got, want)
	}
	if got, want := [2]int{shop.Rework.Rework, shop.Rework.Deployments}, [2]int{2, 4}; got != want {
		t.Errorf("rework of successes = %v, want %v", got, want)
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
	c := shop.ChangeFail
	if got, want := [3]int{c.Deployments, c.FailureIssues, c.Failed}, [3]int{5, 2, 2}; got != want {
		t.Errorf("change fail deployments, failure issues, failed = %v, want %v", got, want)
	}
	if got, want := [2]any{shop.LeadTime.Commits, shop.LeadTime.Median}, [2]any{3, 4 * time.Hour}; got != want {
		t.Errorf("lead time commits, median = %v, want %v", got, want)
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

// labelsOfColumns are the labels of the periods of columns, in their order.
func labelsOfColumns(columns []Column) []string {
	labels := make([]string, len(columns))
	for i, c := range columns {
		labels[i] = c.Period.Label
	}
	return labels
}

// TestHistoryDropsAColumnNoRowHasDataFor (forsgren#68): the columns are the
// periods, oldest first, each with a row per table row; a period before the
// first deployment, or one the history was not read back to, is no column,
// while a quiet period after a deployment stays, and so does the rolling one
// whenever some row has data.
func TestHistoryDropsAColumnNoRowHasDataFor(t *testing.T) {
	data := Data{Records: []history.Record{
		deployedOn("acme/app", at("2025-08-15T12:00:00Z")),
		deployedOn("acme/app", at("2026-09-01T12:00:00Z")),
	}, Reach: fullyRead()}
	tests := []struct {
		name     string
		readBack time.Time
		want     []string
	}{
		{"read in full", time.Unix(0, 0), []string{"2025 H2", "2026 H1", "Last 6 months"}},
		{"read back to March 2026 only", at("2026-03-01T00:00:00Z"), []string{"Last 6 months"}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			data := data
			data.Reach = readBackTo(tt.readBack)
			columns := History(tableProjects, data, now, 1825)
			if got := labelsOfColumns(columns); !slices.Equal(got, tt.want) {
				t.Fatalf("columns = %v, want %v", got, tt.want)
			}
			if got, want := columns[0].Rows, PeriodRows(tableProjects, data, columns[0].Period); !reflect.DeepEqual(got, want) {
				t.Errorf("%s rows = %+v, want the period's rows %+v", columns[0].Period.Label, got, want)
			}
		})
	}
}

// deployedOn is a successful deployment of repository created at at.
func deployedOn(repository string, at time.Time) history.Record {
	r := deployed(repository, history.StateSuccess, 0)
	r.CreatedAt = at
	return r
}

// TestHalfYearOfHoldsTheDay (forsgren#198): the calendar half-year (UTC) of a
// day, with its label, its first day and the day after its last.
func TestHalfYearOfHoldsTheDay(t *testing.T) {
	type halfYear struct {
		Label      string
		Start, End time.Time
	}
	h1 := halfYear{"2026 H1", at("2026-01-01T00:00:00Z"), at("2026-07-01T00:00:00Z")}
	h2 := halfYear{"2026 H2", at("2026-07-01T00:00:00Z"), at("2027-01-01T00:00:00Z")}
	tests := map[string]struct {
		day  time.Time
		want halfYear
	}{
		"first day of H1":   {at("2026-01-01T00:00:00Z"), h1},
		"last second of H1": {at("2026-06-30T23:59:59Z"), h1},
		"first day of H2":   {at("2026-07-01T00:00:00Z"), h2},
		"a day in H2":       {at("2026-10-02T09:30:00Z"), h2},
	}
	for name, tt := range tests {
		t.Run(name, func(t *testing.T) {
			label, start, end := HalfYearOf(tt.day)
			if got := (halfYear{label, start, end}); got != tt.want {
				t.Errorf("HalfYearOf(%s) = %+v; want %+v", tt.day, got, tt.want)
			}
		})
	}
}

// TestFirstDeploymentIsTheOldestSuccessOfAListedRepository (forsgren#198): a
// failure, another state and a repository the projects do not list do not
// count; no success is false.
func TestFirstDeploymentIsTheOldestSuccessOfAListedRepository(t *testing.T) {
	projects := []config.Project{{Name: "Acme", Repositories: []config.Repository{{Name: "acme/app"}}}}
	record := func(repository string, state history.State, created time.Time) history.Record {
		return history.Record{Repository: repository, State: state, CreatedAt: created}
	}
	data := Data{Records: []history.Record{
		record("acme/app", history.StateSuccess, at("2026-10-02T09:00:00Z")),
		record("acme/app", history.StateSuccess, at("2026-09-04T12:00:00Z")),
		record("acme/app", history.StateFailure, at("2026-08-01T00:00:00Z")),
		record("acme/gone", history.StateSuccess, at("2026-07-01T00:00:00Z")),
	}}
	first, ok := FirstDeployment(projects, data)
	if want := at("2026-09-04T12:00:00Z"); !ok || !first.Equal(want) {
		t.Errorf("want %s, true, got %s, %v", want, first, ok)
	}
	if first, ok := FirstDeployment(projects, Data{}); ok || !first.IsZero() {
		t.Errorf("want zero and false without records, got %s, %v", first, ok)
	}
}

// TestIssueClosedAfterThePeriodIsNotCompletedYetInIt (forsgren#53): a failure
// issue opened before the end of a past period and closed after it was still
// open at the end, so that period counts it as a recovery not completed yet,
// not as a recovery and not as nothing.
func TestIssueClosedAfterThePeriodIsNotCompletedYetInIt(t *testing.T) {
	end := now.Add(-10 * day)
	start := end.Add(-184 * day)
	data := Data{
		Records: []history.Record{appDeployment(1, "", history.StateSuccess, now.Sub(start.Add(day)))},
		Failures: []history.Failure{
			{Repository: "acme/app", Issue: 1, OpenedAt: end.Add(-5 * day), ClosedAt: end.Add(3 * day)},
		},
	}
	data.Reach = fullyRead()
	shop := PeriodRows(tableProjects, data, Period{Label: "past", Start: start, End: end})[0]
	r := shop.Recovery
	if got, want := [2]int{r.Recoveries, r.Unrecovered}, [2]int{0, 1}; got != want {
		t.Errorf("recoveries, not completed yet = %v, want %v", got, want)
	}
}
