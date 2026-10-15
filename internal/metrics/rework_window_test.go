package metrics

import (
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// recoveredAgo is a failed deployment just before a successful one created
// ago before now: the success is rework, the recovery of the failure.
func recoveredAgo(ago time.Duration) []history.Record {
	return []history.Record{failed(ago + time.Hour), fixed(ago)}
}

// TestReworkRatesCountsTheWindow (forsgren#178): a recovering success 45
// days old counts over 90 days but not over 30, one 120 days old over 180 but
// not over 90.
func TestReworkRatesCountsTheWindow(t *testing.T) {
	cases := []struct {
		name                   string
		ago                    time.Duration
		days, deployments, bad int
	}{
		{"45 days over 30", 45 * day, 30, 0, 0},
		{"45 days over 90", 45 * day, 90, 1, 1},
		{"120 days over 90", 120 * day, 90, 0, 0},
		{"120 days over 180", 120 * day, 180, 1, 1},
	}
	for _, c := range cases {
		got := ReworkRates(projects, Data{Records: recoveredAgo(c.ago), DoraDays: c.days}, now)[0]
		if got.Deployments != c.deployments || got.Rework != c.bad {
			t.Errorf("%s: want %d deployments and %d rework, got %+v", c.name, c.deployments, c.bad, got)
		}
	}
}

// TestRowsUseTheDataWindowForRework (forsgren#178): Data.DoraDays reaches the
// rework rate; 0 is 30 days.
func TestRowsUseTheDataWindowForRework(t *testing.T) {
	data := Data{Records: append(recoveredAgo(45*day), recoveredAgo(120*day)...), WorkingHours: 8}
	for days, want := range map[int]int{0: 0, 30: 0, 90: 1, 180: 2} {
		data.DoraDays = days
		if got := Rows(projects[:1], data, now)[0].Rework.Deployments; got != want {
			t.Errorf("Data.DoraDays %d: want %d deployments, got %d", days, want, got)
		}
	}
}

// TestAWithdrawnFailureInsideTheWindowIsNotRework (forsgren#155, #178): a
// success made while a failure issue was open is rework, unless that issue is
// withdrawn, whatever the window.
func TestAWithdrawnFailureInsideTheWindowIsNotRework(t *testing.T) {
	failures := []history.Failure{failureNumbered(1, 50*day)}
	records := []history.Record{fixed(45 * day)}
	if got := ReworkRates(projects, Data{Records: records, Failures: failures, DoraDays: 90}, now)[0]; got.Rework != 1 {
		t.Fatalf("want 1 rework deployment with the issue open, got %+v", got)
	}
	kept := history.WithoutWithdrawn(failures,
		[]history.Withdrawal{{Repository: "acme/app", Issue: 1, Withdrawn: true, Reason: history.ReasonNotPlanned}})
	if got := ReworkRates(projects, Data{
		Records: records, Failures: kept, DoraDays: 90,
	}, now)[0]; got.Rework != 0 || got.Deployments != 1 {
		t.Errorf("want 1 deployment and no rework once withdrawn, got %+v", got)
	}
}
