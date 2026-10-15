package metrics

import (
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// TestRecoveryTimesOverCountsTheRecoveriesOfTheWindow (forsgren#178): a
// recovery whose success was created 45 days ago is counted over 90 days but
// not over 30, one 120 days ago over 180 but not over 90; the median is the
// window's. The failure that started a run may be older than the window.
func TestRecoveryTimesOverCountsTheRecoveriesOfTheWindow(t *testing.T) {
	records := []history.Record{
		failed(2*day + time.Hour), fixed(2 * day), // recovered in 1 h, 2 days ago
		failed(45*day + 5*time.Hour), fixed(45 * day), // 5 h, 45 days ago
		failed(120*day + 9*time.Hour), fixed(120 * day), // 9 h, 120 days ago
	}
	cases := []struct {
		days       int
		recoveries int
		median     time.Duration
	}{
		{30, 1, time.Hour}, {90, 2, 3 * time.Hour}, {180, 3, 5 * time.Hour},
	}
	for _, c := range cases {
		got := RecoveryTimesOver(projects, records, c.days, now)[0]
		if got.Recoveries != c.recoveries || got.Median != c.median {
			t.Errorf("%d days: want %d recoveries, median %v, got %d, %v",
				c.days, c.recoveries, c.median, got.Recoveries, got.Median)
		}
	}
}

// TestRecoveryTimesOverCountsAnOpenRunWhateverItsAge (forsgren#178): a run of
// failures not recovered yet is counted over every window, as before.
func TestRecoveryTimesOverCountsAnOpenRunWhateverItsAge(t *testing.T) {
	for _, days := range []int{30, 90, 180} {
		if got := RecoveryTimesOver(projects, []history.Record{failed(300 * day)}, days, now)[0]; got.Unrecovered != 1 {
			t.Errorf("%d days: want 1 recovery not completed yet, got %d", days, got.Unrecovered)
		}
	}
}

// TestRowsUseTheDataWindowForRecovery (forsgren#178): Data.Days reaches the
// recovery time; 0 is 30 days.
func TestRowsUseTheDataWindowForRecovery(t *testing.T) {
	records := []history.Record{failed(45*day + time.Hour), fixed(45 * day),
		failed(120*day + time.Hour), fixed(120 * day)}
	for days, want := range map[int]int{0: 0, 30: 0, 90: 1, 180: 2} {
		rows := Rows(projects[:1], Data{Records: records, WorkingHours: 8, Days: days}, now)
		if got := rows[0].Recovery.Recoveries; got != want {
			t.Errorf("Data.Days %d: want %d recoveries, got %d", days, want, got)
		}
	}
}
