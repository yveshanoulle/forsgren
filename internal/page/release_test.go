package page

import "testing"

// TestNeedsMoreIsTrueWhenTheCheckCouldNotSettleIt (forsgren#73, step 18): no
// access, a rate limit and a failure need more configuration; ok and empty
// do not.
func TestNeedsMoreIsTrueWhenTheCheckCouldNotSettleIt(t *testing.T) {
	for check, want := range map[string]bool{
		"no-access": true, "rate-limited": true, "failed": true, "ok": false, "": false,
	} {
		if got := (Data{NeedsCheck: check}).NeedsMore(); got != want {
			t.Errorf("NeedsMore for %q = %v, want %v", check, got, want)
		}
	}
}
