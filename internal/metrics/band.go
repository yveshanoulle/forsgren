package metrics

import "github.com/yveshanoulle/forsgren/internal/config"

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
//   - On demand (multiple deploys per day): more than once an hour over a
//     working day of working_hours (8 unless configured), so more than
//     working_hours × 30 in 30 days: 241 and more at 8 (forsgren#71).
//   - Between once per hour and once per day: 30 up to that threshold, 30 to
//     240 at 8.
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
)

// WorkingDay is the hours of a working day: hours itself, or the default 8
// when it is not set (below 1).
func WorkingDay(hours int) int {
	if hours < 1 {
		return config.DefaultWorkingHours
	}
	return hours
}

// OnDemandFrom is the lowest 30-day count that is on demand: once an hour
// over a working day of the given hours is hours × 30 deployments in 30
// days, so on demand is more than that (forsgren#69, #71): 241 at 8.
func OnDemandFrom(hours int) int { return WorkingDay(hours)*last30Days + 1 }

// BandOf is the band of the counts of successful deployments in the last 30
// and the last 180 days, for a working day of the given hours (forsgren#71).
func BandOf(last30, last180, workingHours int) Band {
	switch {
	case last30 >= OnDemandFrom(workingHours):
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
