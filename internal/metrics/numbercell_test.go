package metrics

import (
	"testing"
	"time"
)

// TestFrequencyNumberCell (forsgren#46): the successful deployments of the
// last 30 days; 0 where there are none, even with some in the last 180.
func TestFrequencyNumberCell(t *testing.T) {
	wantCells(t, map[string][2]string{
		"none":          {Frequency{}.NumberCell(), "0"},
		"30 days":       {Frequency{Last30: 7, Last180: 9}.NumberCell(), "7"},
		"only 180 days": {Frequency{Last180: 3}.NumberCell(), "0"},
	})
}

// TestLeadTimeNumberCell (forsgren#46): the median in the standard cell's
// short units, no band and no count; "-" without commits.
func TestLeadTimeNumberCell(t *testing.T) {
	lead := func(commits int, median time.Duration) string {
		return LeadTime{Commits: commits, Median: median, Band: LeadTimeBandOf(median)}.NumberCell()
	}
	wantCells(t, map[string][2]string{
		"none":        {LeadTime{}.NumberCell(), "-"},
		"seconds":     {lead(1, 59*time.Second), "less than 1 min"},
		"minutes":     {lead(3, 17*time.Minute+59*time.Second), "17 min"},
		"hours":       {lead(48, 2*time.Hour+7*time.Minute), "2 h 7 min"},
		"whole hours": {lead(2, 2*time.Hour), "2 h"},
		"days":        {lead(2, 3*day+4*time.Hour+59*time.Minute), "3 d 4 h"},
	})
}

// TestRecoveryNumberCell (forsgren#46): the median of the completed
// recoveries; "-" with none completed, open runs or no failures alike.
func TestRecoveryNumberCell(t *testing.T) {
	two := Recovery{Recoveries: 2, Median: 3 * time.Hour, Band: LessThanOneDay}
	open := two
	open.Unrecovered = 1
	wantCells(t, map[string][2]string{
		"none":           {Recovery{}.NumberCell(), "-"},
		"recovered":      {two.NumberCell(), "3 h"},
		"and one open":   {open.NumberCell(), "3 h"},
		"only open ones": {Recovery{Unrecovered: 2}.NumberCell(), "-"},
	})
}

// TestChangeFailNumberCell (forsgren#46): the rate in whole percent; "-"
// without deployments, failure issues or not.
func TestChangeFailNumberCell(t *testing.T) {
	wantCells(t, map[string][2]string{
		"none":         {ChangeFailRate{}.NumberCell(), "-"},
		"issue only":   {ChangeFailRate{FailureIssues: 2}.NumberCell(), "-"},
		"one of seven": {ChangeFailRate{Deployments: 7, Failed: 1, Band: TwentyPercent}.NumberCell(), "14%"},
		"none failed":  {ChangeFailRate{Deployments: 3, Band: ZeroPercent}.NumberCell(), "0%"},
	})
}

// TestReworkNumberCell (forsgren#46): the rate in whole percent; "-"
// without successful deployments.
func TestReworkNumberCell(t *testing.T) {
	wantCells(t, map[string][2]string{
		"none":         {ReworkRate{}.NumberCell(), "-"},
		"one of seven": {ReworkRate{Deployments: 7, Rework: 1, Band: TwentyPercent}.NumberCell(), "14%"},
		"none rework":  {ReworkRate{Deployments: 3, Band: ZeroPercent}.NumberCell(), "0%"},
	})
}

// TestYoungProjectNumberCellIsThePlainCount (forsgren#70): a project younger
// than 30 days shows its plain 30-day count, never the count its band scales
// to (19 in 9 days is banded as 63).
func TestYoungProjectNumberCellIsThePlainCount(t *testing.T) {
	if got := shopWithSuccessesAt(t, youngAges(19, 9*day)...).NumberCell(); got != "19" {
		t.Errorf("want the plain count 19, got %q", got)
	}
}
