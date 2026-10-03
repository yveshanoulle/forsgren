package metrics

import (
	"testing"
	"time"
)

// TestLeadTimeBandOfEachEdge pins the six bands at their edges (forsgren#16,
// ruling 6): each band starts at its lower edge, included, and ends just
// below the next one. A month is 30 days and six months 180 days.
func TestLeadTimeBandOfEachEdge(t *testing.T) {
	cases := []struct {
		median time.Duration
		want   LeadTimeBand
	}{
		{0, LessThanOneHour},
		{time.Hour - time.Second, LessThanOneHour},
		{time.Hour, LessThanOneDay},
		{24*time.Hour - time.Second, LessThanOneDay},
		{24 * time.Hour, OneDayToOneWeek},
		{7*day - time.Second, OneDayToOneWeek},
		{7 * day, OneWeekToOneMonth},
		{30*day - time.Second, OneWeekToOneMonth},
		{30 * day, OneToSixMonths},
		{180*day - time.Second, OneToSixMonths},
		{180 * day, MoreThanSixMonths},
		{3000 * day, MoreThanSixMonths},
	}
	for _, c := range cases {
		if got := LeadTimeBandOf(c.median); got != c.want {
			t.Errorf("LeadTimeBandOf(%v): want band %d (%v), got %d (%v)", c.median, c.want, c.want, got, got)
		}
	}
}

// TestLeadTimeBandNames: the name the page shows for each band, the DORA
// Quick Check's ranges in words; never Elite, High, Medium or Low.
func TestLeadTimeBandNames(t *testing.T) {
	want := map[LeadTimeBand]string{
		LessThanOneHour:   "Less than one hour",
		LessThanOneDay:    "Less than one day",
		OneDayToOneWeek:   "One day to one week",
		OneWeekToOneMonth: "One week to one month",
		OneToSixMonths:    "One to six months",
		MoreThanSixMonths: "More than six months",
		LeadTimeBand(0):   "No band",
		LeadTimeBand(7):   "No band",
	}
	for b, name := range want {
		if got := b.String(); got != name {
			t.Errorf("LeadTimeBand(%d): want %q, got %q", int(b), name, got)
		}
	}
}
