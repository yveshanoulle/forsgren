package metrics

import (
	"testing"
	"time"
)

// The report period (forsgren#542, decision #543 A): the real rolling bounds
// of the DORA window, to the minute in UTC, from the same source the metrics
// count with.

// TestReportBoundsAreTheRollingWindow: the start is the render time less the
// window's days, the end the render time, both UTC; no dora_days is 30 days.
func TestReportBoundsAreTheRollingWindow(t *testing.T) {
	zone := time.FixedZone("CEST", 2*60*60)
	at := time.Date(2026, 10, 27, 0, 29, 40, 0, zone)
	for days, want := range map[int]time.Time{
		0:   time.Date(2026, 9, 26, 22, 29, 40, 0, time.UTC),
		30:  time.Date(2026, 9, 26, 22, 29, 40, 0, time.UTC),
		90:  time.Date(2026, 7, 28, 22, 29, 40, 0, time.UTC),
		180: time.Date(2026, 4, 29, 22, 29, 40, 0, time.UTC),
	} {
		start, end := ReportBounds(days, at)
		if !isUTCInstant(start, want) || !isUTCInstant(end, at) {
			t.Errorf("dora_days %d: want %v to %v in UTC, got %v to %v", days, want, at.UTC(), start, end)
		}
	}
}

// isUTCInstant reports whether got is the same instant as want and carries
// the UTC location.
func isUTCInstant(got, want time.Time) bool {
	return got.Equal(want) && got.Location() == time.UTC
}

// TestReportBoundsHoldTheSameInstantsAsTheWindow: a time at the start is in
// the window, one a second before is not, as window.holds counts.
func TestReportBoundsHoldTheSameInstantsAsTheWindow(t *testing.T) {
	start, end := ReportBounds(30, now)
	w := window(30)
	for _, c := range []struct {
		name string
		at   time.Time
		held bool
	}{
		{"the start", start, true},
		{"a second before the start", start.Add(-time.Second), false},
		{"the end", end, true},
	} {
		if w.holds(c.at, now) != c.held {
			t.Errorf("%s (%v): want held %v, window %v to %v", c.name, c.at, c.held, start, end)
		}
	}
}
