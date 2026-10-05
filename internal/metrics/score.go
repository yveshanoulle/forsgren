package metrics

import "math"

// BandScore is the DORA Quick Check score, 0 to 10, of a categorical band
// (dora.dev/quickcheck): the Quick Check numbers a metric's six answers 1 to
// 6 from the slowest up, so the answer is 7 minus the band, and the score
// is (answer - 1) x 2, which is 10, 8, 6, 4, 2 and 0 from the fastest band
// to the slowest. It serves both band types of the three categorical
// metrics (Band, LeadTimeBand).
func BandScore[B ~int](b B) float64 { return float64(6-b) * 2 }

// PercentScore is the DORA Quick Check score, 0 to 10, of a percent metric
// (dora.dev/quickcheck), change fail rate or deployment rework rate: the
// Quick Check's scale is the percent itself, so the score is 10 minus a
// tenth of the whole percent Percent gives, rounded down: 0% scores 10, 14%
// scores 8.6, 47% scores 5.3 and 100% scores 0. It is computed as
// (100 - percent) / 10, one division that rounds once, so each score is the
// float nearest its one-decimal value and prints as that decimal ("3.9" for
// 61%); 10 - percent/10 would round twice.
func PercentScore(percent int) float64 { return float64(100-percent) / 10 }

// OverallScore is the DORA Quick Check's Overall Performance
// (dora.dev/quickcheck): the mean of the scores it is given, each metric
// weighing the same, rounded to one decimal, half away from zero. A metric
// without data has no score and is not passed in, so the mean is of the
// scored metrics only. ok is false when there is no score at all: then
// there is no Overall Performance.
func OverallScore(scores []float64) (overall float64, ok bool) {
	if len(scores) == 0 {
		return 0, false
	}
	var sum float64
	for _, s := range scores {
		sum += s
	}
	return math.Round(sum/float64(len(scores))*10) / 10, true
}
