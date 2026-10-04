package metrics

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
// scores 8.6, 47% scores 5.3 and 100% scores 0.
func PercentScore(percent int) float64 { return 10 - float64(percent)/10 }
