package metrics

import "testing"

// TestIntegrationCellsWriteTheShareAndTheLongestGap (forsgren#622, step 2): the
// share of regular developers is written like the page's shares, the longest gap
// as a whole number, and both are a dash without developers or gaps.
func TestIntegrationCellsWriteTheShareAndTheLongestGap(t *testing.T) {
	for name, c := range map[string]struct {
		in    Integration
		share string
		gap   string
	}{
		"none": {Integration{}, "-", "-"},
		"some": {Integration{Active: 12, Regular: 5, Gap: CountSpread{Count: 9}, GapLongest: 9}, "41%", "9"},
		"all": {Integration{Active: 1, Regular: 1, Gap: CountSpread{Count: 1}, GapLongest: 1200},
			"100%", GroupDigits(1200)},
		"nobody":  {Integration{Active: 3}, "0%", "-"},
		"a tenth": {Integration{Active: 30, Regular: 1, Gap: CountSpread{Count: 2}}, Decimal("3", "3") + "%", "0"},
	} {
		if got := c.in.RegularCell(); got != c.share {
			t.Errorf("%s: RegularCell = %q, want %q", name, got, c.share)
		}
		if got := c.in.GapLongestCell(); got != c.gap {
			t.Errorf("%s: GapLongestCell = %q, want %q", name, got, c.gap)
		}
	}
}
