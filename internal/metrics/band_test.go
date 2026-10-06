package metrics

import "testing"

// TestBandOfEachEdge pins the six bands at their edges (forsgren#16, step
// 6). The 30-day count decides when it has any deployment: 241 and more
// (more than once an hour over an 8-hour day) is on demand, 30 to 240 between once per hour
// and once per day, 5 to 29 between once per day and once per week, 1 to 4
// between once per week and once per month. With none in 30 days the
// 180-day count decides: 1 and more is between once per month and once
// every six months, 0 less than once per six months.
func TestBandOfEachEdge(t *testing.T) {
	cases := []struct {
		last30, last180 int
		want            Band
	}{
		{5000, 5000, OnDemand},
		{719, 719, OnDemand},
		{241, 241, OnDemand},
		{240, 240, HourlyToDaily},
		{30, 30, HourlyToDaily},
		{29, 400, DailyToWeekly},
		{5, 5, DailyToWeekly},
		{4, 4, WeeklyToMonthly},
		{1, 90, WeeklyToMonthly},
		{0, 40, MonthlyToSixMonthly},
		{0, 1, MonthlyToSixMonthly},
		{0, 0, LessThanSixMonthly},
	}
	for _, c := range cases {
		if got := BandOf(c.last30, c.last180); got != c.want {
			t.Errorf("BandOf(%d, %d): want band %d (%v), got %d (%v)",
				c.last30, c.last180, c.want, c.want, got, got)
		}
	}
}

// TestBandNames: the name the page shows for each band, the DORA Quick
// Check's answer word for word.
func TestBandNames(t *testing.T) {
	want := map[Band]string{
		OnDemand:            "On demand (multiple deploys per day)",
		HourlyToDaily:       "Between once per hour and once per day",
		DailyToWeekly:       "Between once per day and once per week",
		WeeklyToMonthly:     "Between once per week and once per month",
		MonthlyToSixMonthly: "Between once per month and once every six months",
		LessThanSixMonthly:  "Less than once per six months",
		Band(0):             "No band",
		Band(99):            "No band",
	}
	for b, name := range want {
		if got := b.String(); got != name {
			t.Errorf("Band(%d): want %q, got %q", int(b), name, got)
		}
	}
}
