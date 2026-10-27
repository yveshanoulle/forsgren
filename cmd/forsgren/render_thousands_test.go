package main

import (
	"path/filepath"
	"strings"
	"testing"
)

// TestRenderWritesCountsWithTheConfiguredThousandsSeparator (forsgren#528): the
// legend's 1441 deployments on demand over 180 days is written with the
// narrow no-break space by default, with a comma for comma and bare for none;
// a rejected value leaves the default.
func TestRenderWritesCountsWithTheConfiguredThousandsSeparator(t *testing.T) {
	pinNow(t)
	for keys, want := range map[string]string{"": "1 441", "thousands_separator: comma\n": "1,441",
		"thousands_separator: none\n": "1441", "thousands_separator: period\n": "1 441"} {
		dir := filepath.Join(t.TempDir(), "site")
		cfg := writeConfig(t, "version: 1\ndora_days: 180\n"+keys+"projects: []\n")
		if code, _, stderr := runCommand("render", "--out", dir, "--config", cfg); code != 0 {
			t.Fatalf("want exit 0, got %d (stderr %q)", code, stderr)
		}
		if legend := readFile(t, filepath.Join(dir, "legend.html")); !strings.Contains(legend, want+" and more in 180 days") {
			t.Errorf("%q: want the legend to say %q and more in 180 days, got:\n%s", keys, want, legend)
		}
	}
}
