package main

import (
	"path/filepath"
	"strings"
	"testing"
)

// renderLegend renders a site from a config with the keys and returns the
// legend and settings pages, with the stderr of the render.
func renderLegend(t *testing.T, keys string) (legend, settings, stderr string) {
	t.Helper()
	pinNow(t)
	dir := filepath.Join(t.TempDir(), "site")
	cfg := writeConfig(t, "version: 1\ndora_days: 180\n"+keys+"projects: []\n")
	code, _, stderr := runCommand("render", "--out", dir, "--config", cfg)
	if code != 0 {
		t.Fatalf("want exit 0, got %d (stderr %q)", code, stderr)
	}
	return readFile(t, filepath.Join(dir, "legend.html")), readFile(t, filepath.Join(dir, "settings.html")), stderr
}

// TestRenderWritesDecimalsWithTheConfiguredMark (forsgren#536): the legend's
// score range 9 to 7.1 and its 1441 deployments are written with each
// accepted pair of separators; a period with a decimal comma, a comma with the
// point, nothing with a comma.
func TestRenderWritesDecimalsWithTheConfiguredMark(t *testing.T) {
	for keys, want := range map[string][2]string{
		"": {"9 to 7.1", "1\u202f441 and more"}, "decimal_separator: point\n": {"9 to 7.1", "1\u202f441 and more"},
		"decimal_separator: comma\n":                              {"9 to 7,1", "1\u202f441 and more"},
		"thousands_separator: period\ndecimal_separator: comma\n": {"9 to 7,1", "1.441 and more"},
		"thousands_separator: comma\ndecimal_separator: point\n":  {"9 to 7.1", "1,441 and more"},
		"thousands_separator: none\ndecimal_separator: comma\n":   {"9 to 7,1", "1441 and more"}} {
		legend, _, stderr := renderLegend(t, keys)
		if !strings.Contains(legend, want[0]) || !strings.Contains(legend, want[1]) || stderr != "" {
			t.Errorf("%q: want %q and %q in the legend and no warning, got stderr %q and:\n%s", keys, want[0], want[1],
				stderr, legend)
		}
	}
}

// TestRenderUsesBothDefaultsForASeparatorConflict (forsgren#536, decision #537
// A): the same mark for both separators is warned about on stderr for each
// key, the page uses the narrow space and the point, and the settings page
// shows both rows as not accepted, the conflict as the reason.
func TestRenderUsesBothDefaultsForASeparatorConflict(t *testing.T) {
	for keys, mark := range map[string]string{
		"thousands_separator: comma\ndecimal_separator: comma\n":  ",",
		"thousands_separator: period\ndecimal_separator: point\n": "."} {
		legend, settings, stderr := renderLegend(t, keys)
		if !strings.Contains(legend, "9 to 7.1") || !strings.Contains(legend, "1\u202f441 and more") {
			t.Errorf("%q: want both defaults on the legend, got:\n%s", keys, legend)
		}
		wantWarnings(t, keys, stderr)
		want := "are both the mark &#34;" + mark + "&#34;; use different marks; both separators revert to their " +
			"defaults, narrow_space and point. Using the default"
		if strings.Count(settings, want) != 2 || strings.Count(settings, "is not accepted: ") != 2 {
			t.Errorf("%q: want both separator rows not accepted with the conflict, got:\n%s", keys, settings)
		}
	}
}

// wantWarnings fails t unless stderr has a config warning for each separator key.
func wantWarnings(t *testing.T, keys, stderr string) {
	t.Helper()
	for _, key := range []string{"thousands_separator", "decimal_separator"} {
		if !strings.Contains(stderr, "config: warning: ") || !strings.Contains(stderr, key) {
			t.Errorf("%q: want a warning for %s on stderr, got %q", keys, key, stderr)
		}
	}
}

// TestCheckConfigRefusesASeparatorConflictWithItsReason (forsgren#536,
// decision #537 A): check-config stays OK (the run goes on with the defaults)
// and counts both keys as not accepted, printing the reason.
func TestCheckConfigRefusesASeparatorConflictWithItsReason(t *testing.T) {
	cfg := writeConfig(t, "version: 1\nthousands_separator: comma\ndecimal_separator: comma\nprojects: []\n")
	code, stdout, stderr := runCommand("check-config", "--config", cfg)
	if code != 0 || !strings.Contains(stdout, "settings not accepted: 2") ||
		!strings.Contains(stderr, "thousands_separator comma and decimal_separator comma are both the mark") {
		t.Errorf("want exit 0, two settings not accepted and the reason, got %d, %q, %q", code, stdout, stderr)
	}
}
