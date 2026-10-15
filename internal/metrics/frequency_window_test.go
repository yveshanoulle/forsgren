package metrics

import (
	"testing"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// shopOver is Acme Shop's frequency for records over a window of days.
func shopOver(records []history.Record, days int) Frequency {
	return DeploymentFrequency(projects, Data{
		Records: records, WorkingHours: config.DefaultWorkingHours, DoraDays: days,
	}, now)[0]
}

// TestDeploymentFrequencyCountsTheWindow (forsgren#178): a deployment 45
// days old counts over 90 days but not over 30, one 120 days old over 180 but
// not over 90; the shown count, the band, the numbers view and the weekend
// column are the window's.
func TestDeploymentFrequencyCountsTheWindow(t *testing.T) {
	const monthly = "Between once per month and once every six months"
	old := success(250 * day)
	cases := []struct {
		name         string
		records      []history.Record
		days         int
		number, cell string
	}{
		{"45 days over 30", []history.Record{old, success(45 * day)}, 30, "0", monthly + " \u00b7 1"},
		{"45 days over 90", []history.Record{old, success(45 * day)}, 90, "1", monthly + " \u00b7 1"},
		{"120 days over 90", []history.Record{old, success(120 * day)}, 90, "0", monthly + " \u00b7 1"},
		{"120 days over 180", []history.Record{old, success(120 * day)}, 180, "1", monthly + " \u00b7 1"},
		{"two of three over 90", []history.Record{old, success(45 * day), success(50 * day), success(120 * day)},
			90, "2", monthly + " \u00b7 2"},
		{"three over 90", []history.Record{old, success(45 * day), success(50 * day), success(60 * day)},
			90, "3", "Between once per week and once per month \u00b7 3"},
	}
	for _, c := range cases {
		f := shopOver(c.records, c.days)
		if f.NumberCell() != c.number {
			t.Errorf("%s: want number %s, got %s", c.name, c.number, f.NumberCell())
		}
		if got := f.Cell(); got != c.cell {
			t.Errorf("%s: want cell %q, got %q", c.name, c.cell, got)
		}
	}
}

// TestDeploymentFrequencyCountsWeekendsOfTheWindow (forsgren#178): a
// Saturday 42 days ago is a weekend deployment over 90 days, not over 30.
func TestDeploymentFrequencyCountsWeekendsOfTheWindow(t *testing.T) {
	records := []history.Record{success(250 * day), success(42 * day)}
	if got := shopOver(records, 30).WeekendNumberCell(); got != "0" {
		t.Errorf("over 30 days: want 0 weekend deployments, got %s", got)
	}
	if got := shopOver(records, 90).WeekendNumberCell(); got != "1" {
		t.Errorf("over 90 days: want 1 weekend deployment, got %s", got)
	}
}

// TestRowsUseTheDataWindowForFrequency (forsgren#178): Data.DoraDays reaches the
// deployment frequency; 0 is 30 days.
func TestRowsUseTheDataWindowForFrequency(t *testing.T) {
	records := []history.Record{success(250 * day), success(45 * day)}
	for days, want := range map[int]string{0: "0", 30: "0", 90: "1", 180: "1"} {
		rows := Rows(projects[:1], Data{Records: records, WorkingHours: 8, DoraDays: days}, now)
		if got := rows[0].Frequency.NumberCell(); got != want {
			t.Errorf("Data.DoraDays %d: want %s deployments, got %s", days, want, got)
		}
	}
}
