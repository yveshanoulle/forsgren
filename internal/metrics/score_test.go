package metrics

import "testing"

// TestBandScoreEachBand pins the DORA Quick Check score of the six bands of
// the categorical metrics: the fastest band scores 10 and each slower band
// two less, down to 0 for the slowest. Lead time and recovery share
// LeadTimeBand, deployment frequency has Band.
func TestBandScoreEachBand(t *testing.T) {
	cases := []struct {
		name      string
		got, want float64
	}{
		{"lead time less than one hour", BandScore(LessThanOneHour), 10},
		{"lead time less than one day", BandScore(LessThanOneDay), 8},
		{"lead time one day to one week", BandScore(OneDayToOneWeek), 6},
		{"lead time one week to one month", BandScore(OneWeekToOneMonth), 4},
		{"lead time one to six months", BandScore(OneToSixMonths), 2},
		{"lead time more than six months", BandScore(MoreThanSixMonths), 0},
		{"frequency on demand", BandScore(OnDemand), 10},
		{"frequency hourly to daily", BandScore(HourlyToDaily), 8},
		{"frequency daily to weekly", BandScore(DailyToWeekly), 6},
		{"frequency weekly to monthly", BandScore(WeeklyToMonthly), 4},
		{"frequency monthly to six monthly", BandScore(MonthlyToSixMonthly), 2},
		{"frequency less than six monthly", BandScore(LessThanSixMonthly), 0},
	}
	for _, c := range cases {
		if c.got != c.want {
			t.Errorf("%s: want score %v, got %v", c.name, c.want, c.got)
		}
	}
}
