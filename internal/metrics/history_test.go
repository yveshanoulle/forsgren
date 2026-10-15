package metrics

import (
	"reflect"
	"slices"
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
	got := PeriodRows(tableProjects, data, rolling)
	data.DoraDays = 180
	want := Rows(tableProjects, data, now)
	if !reflect.DeepEqual(got, want) {
		t.Errorf("rolling column = %+v, want the rows at 180 days %+v", got, want)
	}
}
