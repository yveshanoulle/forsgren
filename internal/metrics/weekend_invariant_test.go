package metrics

import (
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// shownCounts reads the two numbers the frequency row shows: the
// deployments after the band in the frequency cell and the weekend ones in
// the weekend deployments cell.
func shownCounts(t *testing.T, cell, weekendCell string) (deployments, weekends int) {
	t.Helper()
	parts := strings.Split(cell, cellSeparator)
	if len(parts) != 2 {
		t.Fatalf("want a band and a count, got %q", cell)
	}
	deployments, err := strconv.Atoi(parts[1])
	if err != nil {
		t.Fatalf("want a count in %q: %v", cell, err)
	}
	weekends, err = strconv.Atoi(weekendCell)
	if err != nil {
		t.Fatalf("want a number as the weekend cell, got %q: %v", weekendCell, err)
	}
	return deployments, weekends
}

// onDays are records of state created at noon UTC on the given days of
// month in 2026.
func onDays(state history.State, month time.Month, days ...int) []history.Record {
	var records []history.Record
	for _, day := range days {
		r := deployed("acme/app", state, 0)
		r.CreatedAt = time.Date(2026, month, day, 12, 0, 0, 0, time.UTC)
		records = append(records, r)
	}
	return records
}

// okDays are successes on the given days of month.
func okDays(month time.Month, days ...int) []history.Record {
	return onDays(history.StateSuccess, month, days...)
}

// weekendCase is a history and the two numbers its cell must show.
type weekendCase struct {
	name                         string
	records                      []history.Record
	wantDeployments, wantWeekend int
}

// weekendCases are histories at the pinned now, Saturday 3 October 2026.
// Saturdays and Sundays among the days used: 5, 12, 13, 19, 26 and 27
// September, 27 June, 4 and 5 July.
var weekendCases = []weekendCase{
	{"12 in 30 days, 3 on weekends",
		slices.Concat(okDays(9, 4, 7, 8, 9, 10, 11, 14, 15, 16), okDays(9, 5, 12, 13)), 12, 3},
	{"0 in 30 days, 3 in 180, 1 on a weekend", slices.Concat(okDays(6, 27), okDays(8, 4, 5)), 3, 1},
	{"0 in 30 days, 3 in 180, none on weekends", okDays(8, 4, 5, 6), 3, 0},
	{"0 in 180 days", okDays(3, 21), 0, 0},
	{"weekends only between day 31 and 180", slices.Concat(okDays(10, 1, 2), okDays(6, 27), okDays(7, 4, 5)), 2, 0},
	{"all on weekends", okDays(9, 19, 26, 27), 3, 3},
	{"failures only", onDays(history.StateFailure, 9, 26, 27), 0, 0},
	{"empty", nil, 0, 0},
}

// TestWeekendCountStaysWithinTheCountShown (forsgren#115, decision #121,
// forsgren#124): whatever the history, the weekend deployments cell lies
// between 0 and the count the frequency cell shows, both over the window
// the frequency cell shows, the last 30 days or, with none in them, the
// last 180. Real records go through DeploymentFrequency.
func TestWeekendCountStaysWithinTheCountShown(t *testing.T) {
	for _, c := range weekendCases {
		t.Run(c.name, func(t *testing.T) {
			f := shopOf(t, c.records...)
			frequencyCell, weekendCell := f.Cell(), f.WeekendCell()
			deployments, weekend := shownCounts(t, frequencyCell, weekendCell)
			cell := frequencyCell + " | " + weekendCell
			if weekend < 0 || weekend > deployments {
				t.Errorf("want 0 <= weekend count <= count, got %q", cell)
			}
			if deployments != c.wantDeployments || weekend != c.wantWeekend {
				t.Errorf("want %d deployments, %d on weekends, got %q", c.wantDeployments, c.wantWeekend, cell)
			}
		})
	}
}
