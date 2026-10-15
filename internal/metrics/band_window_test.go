package metrics

import "testing"

// windowEdge is a count over a window and the band it falls in.
type windowEdge struct {
	count int
	want  Band
}

// TestBandOfScalesItsEdgesToTheWindow (forsgren#178): the edges per 30
// days are multiplied by days/30, never the counts: at 8 hours the window of 30
// days starts weekly-to-monthly at 1, daily-to-weekly at 5, hourly-to-daily
// at 30 and on demand at 241; 90 days at 3, 15, 90 and 721; 180 days at 6,
// 30, 180 and 1441. Just below an edge is the band under it. The 180-day count
// splits the slowest two when the window holds too few deployments for
// weekly-to-monthly; at 180 days the window is that count.
func TestBandOfScalesItsEdgesToTheWindow(t *testing.T) {
	cases := map[int][]windowEdge{
		30: {{241, OnDemand}, {240, HourlyToDaily}, {30, HourlyToDaily}, {29, DailyToWeekly},
			{5, DailyToWeekly}, {4, WeeklyToMonthly}, {1, WeeklyToMonthly}, {0, MonthlyToSixMonthly}},
		90: {{721, OnDemand}, {720, HourlyToDaily}, {90, HourlyToDaily}, {89, DailyToWeekly},
			{15, DailyToWeekly}, {14, WeeklyToMonthly}, {3, WeeklyToMonthly}, {2, MonthlyToSixMonthly},
			{1, MonthlyToSixMonthly}},
		180: {{1441, OnDemand}, {1440, HourlyToDaily}, {180, HourlyToDaily}, {179, DailyToWeekly},
			{30, DailyToWeekly}, {29, WeeklyToMonthly}, {6, WeeklyToMonthly}, {5, MonthlyToSixMonthly},
			{1, MonthlyToSixMonthly}, {0, LessThanSixMonthly}},
	}
	for days, edges := range cases {
		for _, e := range edges {
			// The 180-day count is the window's at 180 days, and otherwise at least it.
			last180 := max(e.count, 1)
			if days == 180 {
				last180 = e.count
			}
			if got := BandOf(e.count, last180, 8, days); got != e.want {
				t.Errorf("%d days, %d deployments: want %v, got %v", days, e.count, e.want, got)
			}
		}
	}
}

// TestOnDemandFromScalesWithTheWindow (forsgren#178): more than once an
// hour over a working day is hours times days, plus one.
func TestOnDemandFromScalesWithTheWindow(t *testing.T) {
	for days, want := range map[int]int{30: 241, 90: 721, 180: 1441} {
		if got := OnDemandFrom(8, days); got != want {
			t.Errorf("%d days at 8 hours: want %d, got %d", days, want, got)
		}
	}
	if got := OnDemandFrom(24, 90); got != 2161 {
		t.Errorf("90 days at 24 hours: want 2161, got %d", got)
	}
}

// TestEdgesOfAreTheScaledEdges (forsgren#178): the lowest counts of the
// bands from weekly to monthly up, over each window.
func TestEdgesOfAreTheScaledEdges(t *testing.T) {
	for days, want := range map[int]Edges{30: {1, 5, 30}, 90: {3, 15, 90}, 180: {6, 30, 180}} {
		if got := EdgesOf(days); got != want {
			t.Errorf("%d days: want %+v, got %+v", days, want, got)
		}
	}
}
