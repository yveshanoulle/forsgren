package main

import (
	"os"
	"path/filepath"
	"testing"
)

// daysOn is the config line that keeps the days page, which a config hides
// unless it sets days_page: true, so the tests that compare the whole site or
// its menu with the golden pages keep all the pages (forsgren#159).
const daysOn = "days_page: true\n"

// numbersScoringOn is the config line that lists the numbers and scoring page,
// which a config leaves unlisted unless it sets numbers_scoring_page: true
// (forsgren#55, #200).
const numbersScoringOn = "numbers_scoring_page: true\n"

// historyOn is the config line that lists the history page, which a config
// leaves unlisted unless it sets history_page: true (forsgren#68, #200).
const historyOn = "history_page: true\n"

// writeAllPagesConfig writes the config content with daysOn, numbersScoringOn
// and historyOn added, so every page is written, and returns its path.
func writeAllPagesConfig(t *testing.T, content string) string {
	t.Helper()
	return writeConfig(t, content+daysOn+numbersScoringOn+historyOn)
}

// TestRenderLeavesOutThePagesTheConfigHides (forsgren#159): with --config the
// issues page is written unless issues_page is false, and the days page only
// when days_page is true or unlisted, so a config that sets nothing writes no days page;
// without --config nothing is hidden.
func TestRenderLeavesOutThePagesTheConfigHides(t *testing.T) {
	cases := map[string]struct {
		keys         string
		issues, days bool
	}{
		"config sets nothing": {"", true, false},
		"days on":             {daysOn, true, true},
		"issues off":          {"issues_page: false\n", false, false},
		"both set":            {"issues_page: false\n" + daysOn, false, true},
	}
	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			dir := renderInto(t, "--config", writeConfig(t, validConfig+tc.keys))
			wantPages(t, dir, tc.issues, tc.days)
		})
	}
	t.Run("no --config", func(t *testing.T) {
		wantPages(t, renderInto(t), true, true)
	})
}

// renderInto renders into a fresh folder with the extra arguments and returns it.
func renderInto(t *testing.T, extra ...string) string {
	t.Helper()
	dir := filepath.Join(t.TempDir(), "site")
	if code, _, stderr := runCommand(append([]string{"render", "--out", dir}, extra...)...); code != 0 {
		t.Fatalf("want exit 0, got %d (stderr %q)", code, stderr)
	}
	return dir
}

// wantPages fails unless issues.html and days.html exist in dir exactly as said.
func wantPages(t *testing.T, dir string, issues, days bool) {
	t.Helper()
	for page, want := range map[string]bool{"issues.html": issues, "days.html": days} {
		if _, err := os.Stat(filepath.Join(dir, page)); (err == nil) != want {
			t.Errorf("want %s written: %v, got %v", page, want, err)
		}
	}
}
