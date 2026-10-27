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
		if !start.Equal(want) || !end.Equal(at) || start.Location() != time.UTC || end.Location() != time.UTC {
			t.Errorf("dora_days %d: want %v to %v in UTC, got %v to %v", days, want, at.UTC(), start, end)
		}
	}
}

// TestReportBoundsHoldTheSameInstantsAsTheWindow: a time at the start is in
// the window, one a second before is not, as window.holds counts.
func TestReportBoundsHoldTheSameInstantsAsTheWindow(t *testing.T) {
	start, end := ReportBounds(30, now)
	if w := window(30); !w.holds(start, now) || w.holds(start.Add(-time.Second), now) || !w.holds(end, now) {
		t.Errorf("want the window to hold %v to %v exactly", start, end)
	}
}
