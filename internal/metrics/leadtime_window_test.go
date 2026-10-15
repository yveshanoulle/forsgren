package metrics

import (
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// TestLeadTimesCountsTheCommitsOfTheWindow (forsgren#178): a commit
// deployed 45 days ago is in the lead time over 90 days but not over 30, one
// deployed 120 days ago over 180 but not over 90; the median is the window's.
func TestLeadTimesCountsTheCommitsOfTheWindow(t *testing.T) {
	recent := shippedCommit("acme/app", 2*day, time.Hour)
	at45 := shippedCommit("acme/app", 45*day, 5*time.Hour)
	at120 := shippedCommit("acme/app", 120*day, 9*time.Hour)
	commits := append([]history.Commit{}, recent, at45, at120)
	cases := []struct {
		days int
		want spread
	}{
		{30, spread{1, time.Hour}},
		{90, spread{2, 3 * time.Hour}},
		{180, spread{3, 5 * time.Hour}},
	}
	for _, c := range cases {
		if got := spreadOf(LeadTimes(projects, Data{Commits: commits, DoraDays: c.days}, now)[0]); got != c.want {
			t.Errorf("%d days: want %+v, got %+v", c.days, c.want, got)
		}
	}
}

// TestRowsUseTheDataWindowForLeadTime (forsgren#178): Data.DoraDays reaches the
// lead time; 0 is 30 days.
func TestRowsUseTheDataWindowForLeadTime(t *testing.T) {
	commits := []history.Commit{shippedCommit("acme/app", 45*day, time.Hour),
		shippedCommit("acme/app", 120*day, time.Hour)}
	for days, want := range map[int]int{0: 0, 30: 0, 90: 1, 180: 2} {
		rows := Rows(projects[:1], Data{Commits: commits, WorkingHours: 8, DoraDays: days}, now)
		if got := rows[0].LeadTime.Commits; got != want {
			t.Errorf("Data.DoraDays %d: want %d commits, got %d", days, want, got)
		}
	}
}
