package main

import (
	"path/filepath"
	"strings"
	"testing"
)

// TestTheFixtureSiteCountsAServiceFailureInItsRow (forsgren#515, step 3): the
// failure issue of acme/ios-app that names the rule Beta counts in the Beta
// row's change fail rate, 1 of its 3 deployments, and in the total's, 1 of 12.
func TestTheFixtureSiteCountsAServiceFailureInItsRow(t *testing.T) {
	pinNow(t)
	dir := filepath.Join(t.TempDir(), "site")
	code, _, stderr := runCommand("render", "--out", dir, "--config", fixtureSite+"/forsgren.config.yml",
		"--data", fixtureSite+"/data/deployments.csv")
	if code != 0 {
		t.Fatalf("want exit 0, got %d (stderr %q)", code, stderr)
	}
	page := readFile(t, filepath.Join(dir, "index.html"))
	for name, want := range map[string]string{"Beta": "33% (1 of 3)", "Acme Shop": "8% (1 of 12)"} {
		_, rest, _ := strings.Cut(page, name)
		row, _, _ := strings.Cut(rest, "</tr>")
		if !strings.Contains(row, want) {
			t.Errorf("%s: want %q in its row, got %q", name, want, row)
		}
	}
}
