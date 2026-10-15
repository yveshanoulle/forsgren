package metrics

import (
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// failureNumbered is a failure issue of acme/app with the number issue,
// opened ago before now.
func failureNumbered(issue int64, ago time.Duration) history.Failure {
	f := filed("acme/app", ago)
	f.Issue = issue
	return f
}

// successesAgo is n successful deployments of acme/app created ago before now.
func successesAgo(n int, ago time.Duration) []history.Record {
	return times(n, deployed("acme/app", history.StateSuccess, ago))
}

// TestChangeFailRatesCountsTheWindow (forsgren#178): deployments and a
// failure issue 45 days old count over 90 days but not over 30, those 120 days
// old over 180 but not over 90.
func TestChangeFailRatesCountsTheWindow(t *testing.T) {
	cases := []struct {
		name                   string
		ago                    time.Duration
		days, deployments, bad int
	}{
		{"45 days over 30", 45 * day, 30, 0, 0},
		{"45 days over 90", 45 * day, 90, 4, 1},
		{"120 days over 90", 120 * day, 90, 0, 0},
		{"120 days over 180", 120 * day, 180, 4, 1},
	}
	for _, c := range cases {
		got := ChangeFailRates(projects, Data{
			Records: successesAgo(4, c.ago), Failures: []history.Failure{failureNumbered(1, c.ago)}, DoraDays: c.days,
		}, now)[0]
		if got.Deployments != c.deployments || got.Failed != c.bad || got.FailureIssues != c.bad {
			t.Errorf("%s: want %d deployments and %d failed, got %+v", c.name, c.deployments, c.bad, got)
		}
	}
}

// TestRowsUseTheDataWindowForChangeFailRate (forsgren#178): Data.DoraDays reaches
// the change fail rate; 0 is 30 days.
func TestRowsUseTheDataWindowForChangeFailRate(t *testing.T) {
	data := Data{Records: append(successesAgo(2, 45*day), successesAgo(2, 120*day)...),
		Failures: []history.Failure{failureNumbered(1, 45*day)}, WorkingHours: 8}
	for days, want := range map[int]int{0: 0, 30: 0, 90: 2, 180: 4} {
		data.DoraDays = days
		if got := Rows(projects[:1], data, now)[0].ChangeFail.Deployments; got != want {
			t.Errorf("Data.DoraDays %d: want %d deployments, got %d", days, want, got)
		}
	}
}

// TestAWithdrawnFailureInsideTheWindowIsNotCounted (forsgren#155, #178): the
// failures are those left after the withdrawn ones are dropped, so a withdrawn
// issue opened inside the 90-day window adds nothing.
func TestAWithdrawnFailureInsideTheWindowIsNotCounted(t *testing.T) {
	failures := []history.Failure{failureNumbered(1, 45*day), failureNumbered(2, 50*day)}
	kept := history.WithoutWithdrawn(failures,
		[]history.Withdrawal{{Repository: "acme/app", Issue: 2, Withdrawn: true, Reason: history.ReasonNotPlanned}})
	got := ChangeFailRates(projects, Data{Records: successesAgo(4, 45*day), Failures: kept, DoraDays: 90}, now)[0]
	if got.FailureIssues != 1 || got.Failed != 1 {
		t.Errorf("want 1 failure issue and 1 failed change, got %+v", got)
	}
}
