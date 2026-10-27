package main

import (
	"path/filepath"
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// doraHistory is acme/api's history for the window tests: one success long
// before any window, and one 45 days before renderNow.
func doraHistory() []history.Record {
	ok := history.StateSuccess
	return []history.Record{
		shipped(1, "acme/api", ok, "2025-12-01T12:00:00Z"),
		shipped(2, "acme/api", ok, "2026-08-19T12:00:00Z"),
	}
}

// numbersOf is the numbers view of Acme Shop's frequency cells with the
// config keys written before validConfig.
func numbersOf(t *testing.T, keys string) string {
	t.Helper()
	_, _, index := renderWith(t, "--config", writeConfig(t, "view: numbers\n"+keys+validConfig),
		"--data", writeHistory(t, doraHistory()))
	return index
}

// TestRenderCountsTheConfiguredWindow (forsgren#178): a deployment 45 days
// old is counted in the table with dora_days: 90 and not with the default 30.
func TestRenderCountsTheConfiguredWindow(t *testing.T) {
	pinNow(t)
	const counted = `<td class="num">1</td>`
	thirty, ninety := numbersOf(t, ""), numbersOf(t, "dora_days: 90\n")
	if !strings.Contains(ninety, counted) || strings.Contains(thirty, counted) {
		t.Errorf("want the deployment counted over 90 days only\n--- 30 ---\n%s\n--- 90 ---\n%s", thirty, ninety)
	}
}

// TestRenderTreatsARejectedWindowAsTheDefault (forsgren#178, #183): a
// dora_days that is not accepted renders the 30 days of the default.
func TestRenderTreatsARejectedWindowAsTheDefault(t *testing.T) {
	pinNow(t)
	if got, want := numbersOf(t, "dora_days: 60\n"), numbersOf(t, ""); got != want {
		t.Errorf("want the default page for a rejected window\n--- got ---\n%s\n--- want ---\n%s", got, want)
	}
}

// TestRenderLegendFollowsTheWindow (forsgren#178): dora_days: 90 reaches the
// legend, a rejected 60 leaves the default text.
func TestRenderLegendFollowsTheWindow(t *testing.T) {
	pinNow(t)
	cases := []struct{ keys, window, edge string }{
		{"dora_days: 90\n", "The window is 90 days (dora_days in forsgren.config.yml).", "721 and more in 90 days"},
		{"dora_days: 60\n", "The window is 30 days (the default; dora_days is not set in forsgren.config.yml).",
			"241 and more in 30 days"},
	}
	for _, c := range cases {
		dir := filepath.Join(t.TempDir(), "site")
		cfg := writeConfig(t, "version: 1\n"+c.keys+"projects: []\n")
		if code, _, stderr := runCommand("render", "--out", dir, "--config", cfg); code != 0 {
			t.Fatalf("want exit 0, got %d (stderr %q)", code, stderr)
		}
		legend := readFile(t, filepath.Join(dir, "legend.html"))
		for _, want := range []string{c.window, c.edge} {
			if !strings.Contains(legend, want) {
				t.Errorf("%s: want the legend to say %q, got:\n%s", c.keys, want, legend)
			}
		}
	}
}
