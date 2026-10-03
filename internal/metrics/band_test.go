package metrics

import "testing"

// TestBandOfEachEdge pins the four bands at their edges: 0 is less than
// monthly, 1 to 4 weekly to monthly, 5 to 30 daily to weekly, above 30 on
// demand.
func TestBandOfEachEdge(t *testing.T) {
	cases := []struct {
		last30 int
		want   Band
	}{
		{0, LessThanMonthly},
		{1, WeeklyToMonthly},
		{4, WeeklyToMonthly},
		{5, DailyToWeekly},
		{30, DailyToWeekly},
		{31, OnDemand},
		{500, OnDemand},
	}
	for _, c := range cases {
		if got := BandOf(c.last30); got != c.want {
			t.Errorf("BandOf(%d): want band %d (%v), got %d (%v)", c.last30, c.want, c.want, got, got)
		}
	}
}

// TestBandNames: the name the page shows for each band.
func TestBandNames(t *testing.T) {
	want := map[Band]string{
		OnDemand:        "On demand (several per day)",
		DailyToWeekly:   "Daily to weekly",
		WeeklyToMonthly: "Weekly to monthly",
		LessThanMonthly: "Less than monthly",
		Band(0):         "No band",
	}
	for b, name := range want {
		if got := b.String(); got != name {
			t.Errorf("Band(%d): want %q, got %q", int(b), name, got)
		}
	}
}
