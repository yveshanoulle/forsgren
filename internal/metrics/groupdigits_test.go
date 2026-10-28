package metrics

import (
	"strings"
	"testing"
	"time"
)

// dec is want with each point of its decimals as the DecimalMark, which the
// cells carry for the page renderer to swap (forsgren#536).
func dec(want string) string { return strings.ReplaceAll(want, ".", DecimalMark) }

// TestDecimalWritesTheMarkBetweenWholeAndFraction (forsgren#536): the one
// writer of a decimal puts the DecimalMark, never a point, between the parts.
func TestDecimalWritesTheMarkBetweenWholeAndFraction(t *testing.T) {
	if got, want := Decimal("6", "0"), "6\ue0000"; got != want {
		t.Errorf("want %q, got %q", want, got)
	}
}

// TestGroupDigits (forsgren#528, decision #529 B): a narrow no-break space
// between each group of three digits from 1000 on, the sign kept in front.
func TestGroupDigits(t *testing.T) {
	for n, want := range map[int]string{
		0: "0", 7: "7", 999: "999", 1000: "1\u202f000", 1282: "1\u202f282", 12345: "12\u202f345",
		123456: "123\u202f456", 1234567: "1\u202f234\u202f567", -5: "-5", -999: "-999", -1000: "-1\u202f000",
		-1234567: "-1\u202f234\u202f567",
	} {
		if got := GroupDigits(n); got != want {
			t.Errorf("GroupDigits(%d) = %q, want %q", n, got, want)
		}
	}
}

// TestCountsOfAThousandOrMoreHaveTheSeparator (forsgren#528): every cell that
// writes a count writes it with GroupDigits, in the standard, the numbers and
// the TBD views alike.
func TestCountsOfAThousandOrMoreHaveTheSeparator(t *testing.T) {
	spread := CountSpread{Count: 3, Mean: 1282.4, Median: 1500, P90: 2000}
	failing := ChangeFailRate{Deployments: 1282, Failed: 1000}
	reworked := ReworkRate{Deployments: 1282, Rework: 1000}
	wantCells(t, map[string][2]string{
		"frequency cell":      {Frequency{InWindow: 1282}.Cell(), Band(0).String() + " · 1\u202f282"},
		"weekend cell":        {Frequency{InWindow: 2000, WeekendInWindow: 1282}.WeekendCell(), "1\u202f282"},
		"frequency number":    {Frequency{InWindow: 1282}.NumberCell(), "1\u202f282"},
		"weekend number":      {Frequency{InWindow: 2000, WeekendInWindow: 1282}.WeekendNumberCell(), "1\u202f282"},
		"lead time count":     {LeadTime{Commits: 1282, Median: 2 * time.Hour}.Cell(), "No band · 2 h (1\u202f282)"},
		"recovery count":      {Recovery{Recoveries: 1282, Median: 3 * time.Hour}.Cell(), "No band · 3 h (1\u202f282)"},
		"unrecovered":         {Recovery{Unrecovered: 1282}.Cell(), "— · 1\u202f282 recoveries not completed yet"},
		"change fail":         {failing.Cell(), failing.Band.String() + " · 78% (1\u202f000 of 1\u202f282)"},
		"rework":              {reworked.Cell(), reworked.Band.String() + " · 78% (1\u202f000 of 1\u202f282)"},
		"push commits":        {PushMeasures{Commits: 1282, Pushes: 12345}.CommitsCell(), "1\u202f282"},
		"push pushes":         {PushMeasures{Commits: 1282, Pushes: 12345}.PushesCell(), "12\u202f345"},
		"deployments":         {DeploymentVolume{Count: 1282}.Cell(), "1\u202f282"},
		"developers":          {Developers{Commits: 5, Count: 1282}.CountCell(), "1\u202f282"},
		"count spread mean":   {spread.MeanCell(), "1\u202f282"},
		"count spread median": {spread.MedianCell(), "1\u202f500"},
		"below a thousand":    {DeploymentVolume{Count: 999}.Cell(), "999"},
		"percent no comma":    {percentCell(100), "100%"},
	})
}
