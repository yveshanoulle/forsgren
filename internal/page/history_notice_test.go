package page

import (
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// day is the UTC time of a day of 2026 and a clock time.
func day(month time.Month, d, hour, min int) time.Time {
	return time.Date(2026, month, d, hour, min, 0, 0, time.UTC)
}

// TestHistoryNoticeSaysWhyThereIsOnePeriod (forsgren#198): while only the last
// 6 months have data, the notice names the first deployment and the first
// half-year with the day it appears, or, when history_days would not reach
// that half-year, the history_days it needs; a half-year that is complete but
// not shown yet is the collection still reading back. The render time is
// fixed in every case.
func TestHistoryNoticeSaysWhyThereIsOnePeriod(t *testing.T) {
	now := day(time.October, 3, 12, 0)
	const keyIn = " in forsgren.config.yml."
	tests := []struct {
		name  string
		first time.Time
		days  int
		want  string
	}{
		{"the first half-year is still to come", day(time.October, 2, 9, 30), 365,
			"Only the last 6 months have data so far: the first deployment is 2026-10-02. " +
				"The first half-year, 2026 H2, appears on 2027-01-01."},
		{"history_days unknown counts as enough", day(time.October, 2, 9, 30), 0,
			"Only the last 6 months have data so far: the first deployment is 2026-10-02. " +
				"The first half-year, 2026 H2, appears on 2027-01-01."},
		{"history_days would not reach it then", day(time.October, 2, 9, 30), 180,
			"Only the last 6 months have data so far: the first deployment is 2026-10-02. " +
				"The first half-year, 2026 H2, appears on 2027-01-01 if history_days is at least 185; " +
				"it is 180, so raise it" + keyIn},
		{"the first half-year is complete and history_days reaches it", day(time.February, 10, 9, 0), 365,
			"Only the last 6 months have data so far: the first deployment is 2026-02-10. " +
				"The first half-year, 2026 H1, is not shown yet: the history is still being read back to its start."},
		{"the first half-year is complete and history_days is short", day(time.February, 10, 9, 0), 200,
			"Only the last 6 months have data so far: the first deployment is 2026-02-10. " +
				"The first half-year, 2026 H1, is not shown because history_days is 200: " +
				"raise it to at least 276" + keyIn},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := historyNotice(tt.first, now, tt.days); got != tt.want {
				t.Errorf("historyNotice(%s, %s, %d) =\n%q\nwant\n%q", tt.first, now, tt.days, got, tt.want)
			}
		})
	}
}

// TestHistoryNoticeIsOnlyForASingleRollingColumn (forsgren#198): with two
// columns, with none, with a single half-year column or with no known first
// deployment, the page has no notice.
func TestHistoryNoticeIsOnlyForASingleRollingColumn(t *testing.T) {
	rolling := metrics.Column{Period: metrics.Period{Label: "Last 6 months", Rolling: true,
		End: day(time.October, 3, 12, 0)}}
	half := metrics.Column{Period: metrics.Period{Label: "2026 H1"}}
	first := day(time.October, 2, 9, 30)
	for name, tc := range map[string]struct {
		columns []metrics.Column
		first   time.Time
		want    bool
	}{
		"one rolling column": {[]metrics.Column{rolling}, first, true},
		"two columns":        {[]metrics.Column{half, rolling}, first, false},
		"no column":          {nil, first, false},
		"one half-year":      {[]metrics.Column{half}, first, false},
		"no first":           {[]metrics.Column{rolling}, time.Time{}, false},
	} {
		data := calculated()
		data.History, data.FirstDeployment, data.HistoryDays = tc.columns, tc.first, 365
		if got := data.HistoryNotice() != ""; got != tc.want {
			t.Errorf("%s: want a notice: %v, got %q", name, tc.want, data.HistoryNotice())
		}
	}
}
