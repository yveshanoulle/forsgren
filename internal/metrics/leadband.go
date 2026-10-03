package metrics

import "time"

// LeadTimeBand is a DORA band for lead time for changes (forsgren#16).
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

// LeadTimeBandOf is the band of a median lead time. Stub: no band yet.
func LeadTimeBandOf(median time.Duration) LeadTimeBand {
	_ = median
	return 0
}

// String is the band's name as the page shows it. Stub: empty.
func (b LeadTimeBand) String() string { return "" }
