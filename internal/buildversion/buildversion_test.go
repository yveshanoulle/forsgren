package buildversion

import "testing"

// TestDevIsNoReleaseNumber (forsgren#340): the development build's version is
// the word dev, which is not three dot-separated numbers, so nothing compares
// it with a release.
func TestDevIsNoReleaseNumber(t *testing.T) {
	if Dev != "dev" {
		t.Errorf("Dev = %q, want %q", Dev, "dev")
	}
}
