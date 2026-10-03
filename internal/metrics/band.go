package metrics

// Band is a DORA band for deployment frequency (forsgren#16, step 6): the
// six answers of the current DORA Quick Check (dora.dev/quickcheck), word
// for word, as mutually exclusive ranges of a count.
//
// The Quick Check asks people how often they deploy; forsgren counts
// instead, so BandOf maps a count onto the answers by its average time
// between deployments, on the same edges as lead time's bands (an hour, a
// day, 7 days, a month of 30 days, six months of 180 days). A band "between
// once per X and once per Y" holds Y and not X, so an average of exactly
// once per Y (one deployment in 30 days is once per month) reads as the
// answer that names it last:
//
//   - On demand (multiple deploys per day): 720 and more in 30 days, once
//     an hour or more often.
//   - Between once per hour and once per day: 30 to 719 in 30 days.
//   - Between once per day and once per week: 5 to 29 in 30 days. Once a
//     week is 30/7, about 4.3 in 30 days, so 5 is the first count at or
//     above it.
//   - Between once per week and once per month: 1 to 4 in 30 days.
//   - Between once per month and once every six months: none in 30 days,
//     1 and more in 180 days.
//   - Less than once per six months: none in 180 days.
//
// The 30-day count decides whenever it holds a deployment; only with none
// in 30 days does the 180-day count tell the two slowest bands apart.
type Band int

// The six bands, fastest first. The zero Band is no band.
const (
	OnDemand Band = iota + 1
	HourlyToDaily
	DailyToWeekly
	WeeklyToMonthly
	MonthlyToSixMonthly
	LessThanSixMonthly
)

// The lowest 30-day count of each band from WeeklyToMonthly up.
const (
	weeklyToMonthlyFrom = 1
	dailyToWeeklyFrom   = 5
	hourlyToDailyFrom   = 30
	onDemandFrom        = 720
)

// BandOf is the band of the counts of successful deployments in the last 30
// and the last 180 days.
func BandOf(last30, last180 int) Band {
	switch {
	case last30 >= onDemandFrom:
		return OnDemand
	case last30 >= hourlyToDailyFrom:
		return HourlyToDaily
	case last30 >= dailyToWeeklyFrom:
		return DailyToWeekly
	case last30 >= weeklyToMonthlyFrom:
		return WeeklyToMonthly
	case last180 > 0:
		return MonthlyToSixMonthly
	default:
		return LessThanSixMonthly
	}
}

// bandNames are the bands' names, indexed by band; index 0 is no band.
var bandNames = [...]string{
	"No band",
	"On demand (multiple deploys per day)",
	"Between once per hour and once per day",
	"Between once per day and once per week",
	"Between once per week and once per month",
	"Between once per month and once every six months",
	"Less than once per six months",
}

// String is the band's name as the page shows it.
func (b Band) String() string { return bandName(b, bandNames[:]) }
