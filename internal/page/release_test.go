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

// TestNewerComparesVersionsAsNumbers (forsgren#40, step 4): 0.0.10 is newer
// than 0.0.9, a leading "v" is ignored, and what is equal, older or not a
// version is never newer.
func TestNewerComparesVersionsAsNumbers(t *testing.T) {
	cases := []struct {
		current, latest string
		want            bool
	}{
		{"0.0.9", "0.0.10", true},
		{"0.0.10", "0.0.9", false},
		{"0.0.10", "0.1.0", true},
		{"0.9.9", "1.0.0", true},
		{"0.0.9", "v0.0.10", true},
		{"v0.0.9", "0.0.10", true},
		{"0.0.9", "0.0.9", false},
		{"0.0.9", "0.0.8", false},
		{"0.0.9", "", false},
		{"0.0.9", "banana", false},
		{"0.0.9", "0.0.10-rc1", false},
		{"banana", "0.0.10", false},
		{"0.0.9", "0.0.99999999999999999999", false},
	}
	for _, c := range cases {
		if got := newer(c.current, c.latest); got != c.want {
			t.Errorf("newer(%q, %q) = %v, want %v", c.current, c.latest, got, c.want)
		}
	}
}

// TestReleaseVersionNamesThePlainVersion (forsgren#40, step 4): a release
// tag's version is its three numbers without the v; anything else is none.
func TestReleaseVersionNamesThePlainVersion(t *testing.T) {
	cases := map[string]string{"v0.0.10": "0.0.10", "0.1.2": "0.1.2", "nightly": "", "v1.2": "", "1.2.3-rc1": ""}
	for in, want := range cases {
		got, ok := ReleaseVersion(in)
		if got != want || ok != (want != "") {
			t.Errorf("ReleaseVersion(%q) = %q, %v, want %q", in, got, ok, want)
		}
	}
}
