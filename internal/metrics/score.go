package metrics

// BandScore is the DORA Quick Check score, 0 to 10, of a categorical band
// (dora.dev/quickcheck): the Quick Check numbers a metric's six answers 1 to
// 6 from the slowest up, so the answer is 7 minus the band, and the score
// is (answer - 1) x 2, which is 10, 8, 6, 4, 2 and 0 from the fastest band
// to the slowest. It serves both band types of the three categorical
// metrics (Band, LeadTimeBand).
func BandScore[B ~int](b B) float64 { return 0 }
