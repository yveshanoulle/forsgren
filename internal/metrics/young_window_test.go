package metrics

import (
	"testing"
	"time"
)

// TestBandOfAgeOverScalesAYoungRowToTheWindow (forsgren#178, #69): a row
// whose first success is younger than the window has not had a whole window
// to deploy in, so its count is scaled to the window, count × days over its
// age in whole days (at least 1), and then banded with the window's edges.
// A row as old as the window or older is not scaled.
func TestBandOfAgeOverScalesAYoungRowToTheWindow(t *testing.T) {
	cases := []struct {
		name        string
		days, count int
		age         time.Duration
		want        Band
	}{
		{"90 days, 20 days old, 6 is 27 in 90", 90, 6, 20 * day, DailyToWeekly},
		{"90 days, 20 days old, 3 is 13 in 90", 90, 3, 20 * day, WeeklyToMonthly},
		{"90 days, 20 days old, 1 is 4 in 90", 90, 1, 20 * day, WeeklyToMonthly},
		{"180 days, 40 days old, 12 is 54 in 180", 180, 12, 40 * day, DailyToWeekly},
		{"180 days, 40 days old, 1 is 4 in 180", 180, 1, 40 * day, MonthlyToSixMonthly},
		{"90 days, 12 hours old counts as 1 day", 90, 1, 12 * time.Hour, HourlyToDaily},
		{"90 days, 80 days old, 14 is 15 in 90", 90, 14, 80 * day, DailyToWeekly},
		{"90 days, exactly 90 days old is not", 90, 14, 90 * day, WeeklyToMonthly},
		{"90 days, 100 days old is not", 90, 6, 100 * day, WeeklyToMonthly},
		{"180 days, 200 days old is not", 180, 12, 200 * day, WeeklyToMonthly},
	}
	for _, c := range cases {
		// A young row's 180-day count is its window count: at least the count.
		got := bandOfAgeOver(c.count, c.count, 8, c.days, now.Add(-c.age), now)
		if got != c.want {
			t.Errorf("%s: want %v, got %v", c.name, c.want, got)
		}
	}
}
