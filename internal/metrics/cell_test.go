package metrics

import (
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// wantCells fails the test for each text that is not the cell it wants.
func wantCells(t *testing.T, cases map[string][2]string) {
	t.Helper()
	for name, c := range cases {
		if c[0] != c[1] {
			t.Errorf("%s: want %q, got %q", name, c[1], c[0])
		}
	}
}

// TestFrequencyCell (forsgren#38): the band and the count that decided it,
// the last 30 days' or, with none in them, the last 180 days'. A row with
// failed deployments only counts no success: its band is the slowest, 0
// (Yves's ruling on decision #35).
func TestFrequencyCell(t *testing.T) {
	latest := now.Add(-day)
	wantCells(t, map[string][2]string{
		"no success": {Frequency{Band: LessThanSixMonthly}.Cell(), "Less than once per six months · 0"},
		"30 days": {Frequency{InWindow: 7, Last180: 9, Latest: latest, Band: DailyToWeekly}.Cell(),
			"Between once per day and once per week · 7"},
		"weekends": {Frequency{InWindow: 12, Last180: 12, WeekendInWindow: 3, Latest: latest, Band: DailyToWeekly}.Cell(),
			"Between once per day and once per week · 12"},
		"180 days": {Frequency{Last180: 3, Latest: latest, Band: MonthlyToSixMonthly}.Cell(),
			"Between once per month and once every six months · 3"},
		"older": {Frequency{Latest: latest, Band: LessThanSixMonthly}.Cell(), "Less than once per six months · 0"},
	})
}

// TestLeadTimeCell (forsgren#38): the band, the median in short units, cut
// down as on the long text, and the count of commits.
func TestLeadTimeCell(t *testing.T) {
	lead := func(commits int, median time.Duration) string {
		return LeadTime{Commits: commits, Median: median, Band: LeadTimeBandOf(median)}.Cell()
	}
	wantCells(t, map[string][2]string{
		"none":         {LeadTime{}.Cell(), "No lead time yet"},
		"seconds":      {lead(1, 59*time.Second), "Less than one hour · less than 1 min (1)"},
		"minutes":      {lead(3, 17*time.Minute+59*time.Second), "Less than one hour · 17 min (3)"},
		"hours":        {lead(48, 2*time.Hour+7*time.Minute), "Less than one day · 2 h 7 min (48)"},
		"whole hours":  {lead(2, 2*time.Hour), "Less than one day · 2 h (2)"},
		"days":         {lead(2, 3*day+4*time.Hour+59*time.Minute), "One day to one week · 3 d 4 h (2)"},
		"a whole week": {lead(5, 7*day), "One week to one month · 7 d (5)"},
	})
}

// TestRecoveryCell (forsgren#38): the band, the median and the count of
// recoveries, and the recoveries not completed yet: a run of failures is
// one, counted as an episode, never as its failed deployments; with none
// completed, no band and no median, "—" (Yves's ruling on decision #35).
func TestRecoveryCell(t *testing.T) {
	two := Recovery{Recoveries: 2, Median: 3 * time.Hour, Band: LessThanOneDay}
	open := two
	open.Unrecovered = 1
	wantCells(t, map[string][2]string{
		"none":           {Recovery{}.Cell(), "No failed deployments"},
		"recovered":      {two.Cell(), "Less than one day · 3 h (2)"},
		"and one open":   {open.Cell(), "Less than one day · 3 h (2) · 1 recovery not completed yet"},
		"only open ones": {Recovery{Unrecovered: 2}.Cell(), "— · 2 recoveries not completed yet"},
		"only one open":  {Recovery{Unrecovered: 1}.Cell(), "— · 1 recovery not completed yet"},
	})
}

// TestChangeFailCell (forsgren#38): the band, the rate in whole percent and
// the failed changes of the deployments.
func TestChangeFailCell(t *testing.T) {
	wantCells(t, map[string][2]string{
		"none":         {ChangeFailRate{}.Cell(), "No deployments"},
		"issue only":   {ChangeFailRate{FailureIssues: 1}.Cell(), "No deployments · 1 failure issue"},
		"issues only":  {ChangeFailRate{FailureIssues: 2}.Cell(), "No deployments · 2 failure issues"},
		"one of seven": {ChangeFailRate{Deployments: 7, Failed: 1, Band: TwentyPercent}.Cell(), "20% · 14% (1 of 7)"},
		"none failed":  {ChangeFailRate{Deployments: 3, Band: ZeroPercent}.Cell(), "0% · 0% (0 of 3)"},
	})
}

// TestFrequencyCellOfTheFallbackEndsWithItsCount (forsgren#115, #124): from
// real records, a project with no success in the last 30 days and 3 in the
// last 180, one of them on a Saturday, shows the 180-day count and nothing
// after it; the weekend count has its own column.
func TestFrequencyCellOfTheFallbackEndsWithItsCount(t *testing.T) {
	at := func(month time.Month, day int) history.Record {
		r := success(0)
		r.CreatedAt = time.Date(2026, month, day, 12, 0, 0, 0, time.UTC)
		return r
	}
	// 27 June is a Saturday, 4 August a Tuesday, 2 September a Wednesday.
	got := shopOf(t, at(time.June, 27), at(time.August, 4), at(time.September, 2)).Cell()
	want := "Between once per month and once every six months · 3"
	if got != want {
		t.Errorf("want %q, got %q", want, got)
	}
}

// TestFrequencyWeekendCell (forsgren#124): the weekend deployments column
// takes its window from the count the frequency cell shows, the last 30
// days or, with none in them, the last 180; 0 when there are none.
func TestFrequencyWeekendCell(t *testing.T) {
	wantCells(t, map[string][2]string{
		"30 days":             {Frequency{InWindow: 12, Last180: 12, WeekendInWindow: 3, Weekend180: 3}.WeekendCell(), "3"},
		"30 days not 180":     {Frequency{InWindow: 12, Last180: 20, WeekendInWindow: 3, Weekend180: 7}.WeekendCell(), "3"},
		"180 days fallback":   {Frequency{Last180: 3, Weekend180: 1}.WeekendCell(), "1"},
		"fallback no weekend": {Frequency{Last180: 3}.WeekendCell(), "0"},
		"no success":          {Frequency{}.WeekendCell(), "0"},
	})
}
