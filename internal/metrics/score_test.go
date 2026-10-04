package metrics

import "testing"

// TestBandScoreEachBand pins the DORA Quick Check score of the six bands of
// the categorical metrics: the fastest band scores 10 and each slower band
// two less, down to 0 for the slowest. Lead time and recovery share
// LeadTimeBand, deployment frequency has Band.
func TestBandScoreEachBand(t *testing.T) {
	checkScores(t, []scoreCase{
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
	})
}

// TestPercentScore pins the DORA Quick Check score of the percent metrics
// from the whole percent Percent gives: 10 at 0%, 0 at 100%, a tenth of a
// point less per percent, and the percent rounded down by Percent first, so
// a rate of 14.9% scores as 14%.
func TestPercentScore(t *testing.T) {
	changeFail := ChangeFailRate{Deployments: 1000, Failed: 149}
	rework := ReworkRate{Deployments: 1000, Rework: 149}
	checkScores(t, []scoreCase{
		{"0 percent", PercentScore(0), 10},
		{"14 percent", PercentScore(14), 8.6},
		{"47 percent", PercentScore(47), 5.3},
		{"100 percent", PercentScore(100), 0},
		{"change fail rate of 14.9 percent", PercentScore(changeFail.Percent()), 8.6},
		{"rework rate of 14.9 percent", PercentScore(rework.Percent()), 8.6},
	})
}

// scoreCase is a score and the score it has to be.
type scoreCase struct {
	name      string
	got, want float64
}

// checkScores reports each case whose score is not the wanted one.
func checkScores(t *testing.T, cases []scoreCase) {
	t.Helper()
	for _, c := range cases {
		if c.got != c.want {
			t.Errorf("%s: want score %v, got %v", c.name, c.want, c.got)
		}
	}
}
