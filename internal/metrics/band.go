package metrics

// Band is a DORA performance band for deployment frequency.
//
// RED STUB (forsgren#12, step 7): the bands and their thresholds land with
// the green.
type Band int

// The four bands, slowest first. The zero Band is no band.
const (
	LessThanMonthly Band = iota + 1
	WeeklyToMonthly
	DailyToWeekly
	OnDemand
)

// BandOf is the band of a count of successful deployments in the last 30
// days. RED STUB: no band yet.
func BandOf(int) Band { return 0 }

// String is the band's name as the page shows it. RED STUB: empty.
func (b Band) String() string { return "" }
