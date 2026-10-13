package metrics

import (
	"fmt"
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// shownCounts reads the two numbers a frequency cell shows: the deployments
// and, after "at weekends", the weekend ones (0 when the cell has no
// suffix).
func shownCounts(t *testing.T, cell string) (deployments, weekends int) {
	t.Helper()
	parts := strings.Split(cell, cellSeparator)
	if len(parts) < 2 || len(parts) > 3 {
		t.Fatalf("want a band, a count and maybe a weekend count, got %q", cell)
	}
	deployments, err := strconv.Atoi(parts[1])
	if err != nil {
		t.Fatalf("want a count in %q: %v", cell, err)
	}
	if len(parts) == 3 {
		if _, err := fmt.Sscanf(parts[2], "%d at weekends", &weekends); err != nil {
			t.Fatalf("want N at weekends in %q: %v", cell, err)
		}
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

// TestWeekendCountStaysWithinTheCountShown (forsgren#115, decision #121):
// whatever the history, the cell's weekend count lies between 0 and the
// count the cell shows, both over the window the cell shows, the last 30
// days or, with none in them, the last 180. Real records go through
// DeploymentFrequency.
func TestWeekendCountStaysWithinTheCountShown(t *testing.T) {
	for _, c := range weekendCases {
		t.Run(c.name, func(t *testing.T) {
			cell := shopOf(t, c.records...).Cell()
			deployments, weekend := shownCounts(t, cell)
			if weekend < 0 || weekend > deployments {
				t.Errorf("want 0 <= weekend count <= count, got %q", cell)
			}
			if deployments != c.wantDeployments || weekend != c.wantWeekend {
				t.Errorf("want %d deployments, %d at weekends, got %q", c.wantDeployments, c.wantWeekend, cell)
			}
		})
	}
}
