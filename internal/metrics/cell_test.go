package metrics

import (
	"testing"
	"time"
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
		"30 days": {Frequency{Last30: 7, Last180: 9, Latest: latest, Band: DailyToWeekly}.Cell(),
			"Between once per day and once per week · 7"},
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
