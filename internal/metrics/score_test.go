package metrics

import (
	"fmt"
	"testing"
)

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

// TestPercentScoreIsExactlyOneDecimal pins that the score of every whole
// percent is exactly the one-decimal number (100 - percent) / 10, the nearest
// float to it, so the page prints 3.9 for 61% and 0.4 for 96%.
func TestPercentScoreIsExactlyOneDecimal(t *testing.T) {
	cases := []scoreCase{
		{"61 percent as a literal", PercentScore(61), 3.9},
		{"96 percent as a literal", PercentScore(96), 0.4},
	}
	for p := 0; p <= 100; p++ {
		cases = append(cases, scoreCase{fmt.Sprintf("%d percent", p), PercentScore(p), float64(100-p) / 10})
	}
	checkScores(t, cases)
}

// TestOverallScoreIsTheMeanToOneDecimal pins the Quick Check's Overall
// Performance: the plain mean of the scores given, rounded to one decimal.
// Its own example, 6, 8, 10, 8.6 and 10, is 8.5; a mean of 7.97 rounds up to
// 8.0; with only some metrics scored the mean is of those.
func TestOverallScoreIsTheMeanToOneDecimal(t *testing.T) {
	overall := func(scores ...float64) float64 {
		got, _ := OverallScore(scores)
		return got
	}
	checkScores(t, []scoreCase{
		{"the Quick Check example", overall(6, 8, 10, 8.6, 10), 8.5},
		{"a mean that rounds up", overall(10, 8.6, 5.3), 8.0},
		{"two scored metrics", overall(10, 8.6), 9.3},
	})
}

// TestOverallScoreRoundsAnExactHalfUp pins how Overall Performance rounds: the
// mean of the scores is taken exactly, as whole tenths, and an exact half
// tenth rounds up, so 4.95 is 5.0 and 2.35 is 2.4, whatever the float sum of
// the scores carries.
func TestOverallScoreRoundsAnExactHalfUp(t *testing.T) {
	overall := func(scores ...float64) float64 {
		got, _ := OverallScore(scores)
		return got
	}
	checkScores(t, []scoreCase{
		{"a mean of exactly 4.95", overall(2, 0, PercentScore(3), PercentScore(19)), 5.0},
		{"a mean of exactly 2.35 from 2.3 and 2.4", overall(2.3, 2.4), 2.4},
		{"a mean of exactly 2.35 from 0.1 and 4.6", overall(0.1, 4.6), 2.4},
	})
}

// TestOverallScoreOfAnyTwoScoresIsTheHalfUpMean pins the same for every pair
// of one-decimal scores from 0 to 10, against the mean of their tenths as
// integers: (a + b) / 2 rounded half up is (a + b + 1) / 2.
func TestOverallScoreOfAnyTwoScoresIsTheHalfUpMean(t *testing.T) {
	var cases []scoreCase
	for a := 0; a <= 100; a++ {
		for b := a; b <= 100; b++ {
			got, _ := OverallScore([]float64{float64(a) / 10, float64(b) / 10})
			want := float64((a+b+1)/2) / 10
			cases = append(cases, scoreCase{fmt.Sprintf("%d and %d tenths", a, b), got, want})
		}
	}
	checkScores(t, cases)
}

// TestOverallScoreOfNoScoreIsNone: with no scored metric there is no
// Overall Performance.
func TestOverallScoreOfNoScoreIsNone(t *testing.T) {
	if got, ok := OverallScore(nil); ok {
		t.Errorf("no scores: want no overall score, got %v", got)
	}
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
