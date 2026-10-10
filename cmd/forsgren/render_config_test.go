package main

import (
	"html"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

const noProjectsLine = "forsgren.config.yml lists the projects"

// renderWith renders into a fresh directory with extra arguments after
// --out and returns the exit status, stderr and the index.html written (empty
// when none was).
func renderWith(t *testing.T, extra ...string) (int, string, string) {
	t.Helper()
	dir := filepath.Join(t.TempDir(), "site")
	code, _, stderr := runCommand(append([]string{"render", "--out", dir}, extra...)...)
	index := ""
	if code == 0 {
		index = readFile(t, filepath.Join(dir, "index.html"))
	}
	return code, stderr, index
}

// TestRenderSaysWhenNoProjectsAreConfigured (forsgren#12, step 3): with a
// config that lists no projects the page shows, besides its version, the line
// that says where the projects are listed (forsgren#41, step 3: with an
// example); it is the page of the golden file.
func TestRenderSaysWhenNoProjectsAreConfigured(t *testing.T) {
	pinNow(t)
	code, stderr, index := renderWith(t, "--config", writeConfig(t, "version: 1\nprojects: []\n"))
	if code != 0 {
		t.Fatalf("want exit 0, got %d (stderr %q)", code, stderr)
	}
	if !strings.Contains(index, "Forsgren 0.4.2") || !strings.Contains(index, noProjectsLine) {
		t.Errorf("want the version and %q on the page, got:\n%s", noProjectsLine, index)
	}
	golden := readFile(t, "../../internal/page/testdata/index.no-projects.golden.html")
	if index != golden {
		t.Errorf("the no-projects page differs from its golden file\n--- got ---\n%s\n--- want ---\n%s", index, golden)
	}
}

// TestRenderWithProjectsHasNoNoProjectsLine: a config with projects, and no
// config at all (the repository's own build), render the page as it was, the
// golden file of the placeholder, without the line.
func TestRenderWithProjectsHasNoNoProjectsLine(t *testing.T) {
	pinNow(t)
	golden := readFile(t, "../../internal/page/testdata/index.golden.html")
	cases := map[string][]string{
		"projects configured": {"--config", writeConfig(t, validConfig)},
		"no --config":         nil,
	}
	for name, extra := range cases {
		t.Run(name, func(t *testing.T) {
			code, stderr, index := renderWith(t, extra...)
			if code != 0 {
				t.Fatalf("want exit 0, got %d (stderr %q)", code, stderr)
			}
			if index != golden {
				t.Errorf("want the placeholder page of index.golden.html, got:\n%s", index)
			}
		})
	}
}

// refusedConfig says whether render refused the config at path: exit 1,
// no index.html written, and stderr starting with `render: <path>: `.
func refusedConfig(code int, stderr, index, path string) bool {
	return code == 1 && index == "" && strings.HasPrefix(stderr, "render: "+path+": ")
}

// TestRenderRefusesAnInvalidOrMissingConfig: render never publishes from a
// config check-config would refuse; it exits 1 with the same refusal, and
// writes nothing.
func TestRenderRefusesAnInvalidOrMissingConfig(t *testing.T) {
	missing := filepath.Join(t.TempDir(), "forsgren.config.yml")
	invalid := writeConfig(t, "version: 1\nprojcts: []\n")
	for name, path := range map[string]string{"missing": missing, "invalid": invalid} {
		t.Run(name, func(t *testing.T) {
			code, stderr, index := renderWith(t, "--config", path)
			if !refusedConfig(code, stderr, index, path) {
				t.Errorf("want exit 1 and `render: <path>: ...`, got %d, %q", code, stderr)
			}
		})
	}
}

// TestRenderUsageNamesTheConfigFlag: the usage lists --config, and an
// unknown flag is still a usage error.
func TestRenderUsageNamesTheConfigFlag(t *testing.T) {
	_, _, stderr := runCommand()
	if !strings.Contains(stderr, "forsgren render --out <dir> [--config <path>]") {
		t.Errorf("want the usage to list render's --config, got %q", stderr)
	}
	code, _, stderr := runCommand("render", "--out", t.TempDir(), "--conf", "x")
	if code != 2 || !strings.Contains(stderr, "flag provided but not defined: -conf") {
		t.Errorf("want exit 2 for an unknown flag, got %d, %q", code, stderr)
	}
}

// howToExample is the example config in the no-projects page's how-to.
var howToExample = regexp.MustCompile(`(?s)<pre><code>(.*?)</code></pre>`)

// TestRenderedHowToPassesCheckConfig (forsgren#41, step 3): the example in
// the page's how-to for an empty config is itself a valid config.
func TestRenderedHowToPassesCheckConfig(t *testing.T) {
	_, _, index := renderWith(t, "--config", writeConfig(t, "version: 1\nprojects: []\n"))
	found := howToExample.FindStringSubmatch(index)
	if found == nil {
		t.Fatalf("want an example config in a pre block on the page, got:\n%s", index)
	}
	path := writeConfig(t, html.UnescapeString(found[1]))
	if code, _, stderr := runCommand("check-config", "--config", path); code != 0 {
		t.Errorf("want the example to pass check-config, got exit %d, %q", code, stderr)
	}
}

// TestRenderLegendFollowsWorkingHours (forsgren#71): a config with
// working_hours: 12 reaches the legend page, its thresholds included.
func TestRenderLegendFollowsWorkingHours(t *testing.T) {
	pinNow(t)
	dir := filepath.Join(t.TempDir(), "site")
	cfg := writeConfig(t, "version: 1\nworking_hours: 12\nprojects: []\n")
	if code, _, stderr := runCommand("render", "--out", dir, "--config", cfg); code != 0 {
		t.Fatalf("want exit 0, got %d (stderr %q)", code, stderr)
	}
	legend := readFile(t, filepath.Join(dir, "legend.html"))
	for _, want := range []string{"A working day is configured as 12 hours.", "361 and more", "30 to 360"} {
		if !strings.Contains(legend, want) {
			t.Errorf("want the legend to say %q, got:\n%s", want, legend)
		}
	}
}

// TestRenderSettingsPageListsTheSettings (forsgren#74, #84): a config with
// only history_days: 30 reaches the settings page, the other keys marked as
// defaults; the legend lists none.
func TestRenderSettingsPageListsTheSettings(t *testing.T) {
	pinNow(t)
	dir := filepath.Join(t.TempDir(), "site")
	cfg := writeConfig(t, "version: 1\nhistory_days: 30\nprojects: []\n")
	if code, _, stderr := runCommand("render", "--out", dir, "--config", cfg); code != 0 {
		t.Fatalf("want exit 0, got %d (stderr %q)", code, stderr)
	}
	settings := readFile(t, filepath.Join(dir, "settings.html"))
	for _, want := range []string{
		"<li>history_days: 30</li>",
		"<li>view: standard (default, not set in forsgren.config.yml)</li>",
	} {
		if !strings.Contains(settings, want) {
			t.Errorf("want the settings page to say %q, got:\n%s", want, settings)
		}
	}
	if legend := readFile(t, filepath.Join(dir, "legend.html")); strings.Contains(legend, "<li>history_days: 30</li>") {
		t.Errorf("want no setting on the legend, got:\n%s", legend)
	}
}
