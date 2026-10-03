package metrics

import "time"

// LeadTimeBand is a DORA band for lead time for changes (forsgren#16,
// ruling 6): the six answers of the current DORA Quick Check, as mutually
// exclusive ranges of the median lead time.
//
// A month is 30 days and six months 180 days, so every edge is a fixed
// duration and a median falls in the same band whatever the calendar:
//
//   - Less than one hour: below 1 hour.
//   - Less than one day: 1 hour to below 24 hours.
//   - One day to one week: 24 hours to below 7 days.
//   - One week to one month: 7 days to below 30 days.
//   - One to six months: 30 days to below 180 days.
//   - More than six months: 180 days and more.
type LeadTimeBand int

// The six bands, fastest first. The zero LeadTimeBand is no band.
const (
	LessThanOneHour LeadTimeBand = iota + 1
	LessThanOneDay
	OneDayToOneWeek
	OneWeekToOneMonth
	OneToSixMonths
	MoreThanSixMonths
)

// month is a lead-time month: 30 days of 24 hours.
const month = 30 * day

// LeadTimeBandOf is the band of a median lead time.
func LeadTimeBandOf(median time.Duration) LeadTimeBand {
	switch {
	case median < time.Hour:
		return LessThanOneHour
	case median < day:
		return LessThanOneDay
	case median < 7*day:
		return OneDayToOneWeek
	case median < month:
		return OneWeekToOneMonth
	case median < 6*month:
		return OneToSixMonths
	default:
		return MoreThanSixMonths
	}
}

// leadTimeBandNames are the bands' names, indexed by band; index 0 is no
// band.
var leadTimeBandNames = [...]string{
	"No band",
	"Less than one hour",
	"Less than one day",
	"One day to one week",
	"One week to one month",
	"One to six months",
	"More than six months",
}

// String is the band's name as the page shows it.
func (b LeadTimeBand) String() string { return bandName(b, leadTimeBandNames[:]) }
