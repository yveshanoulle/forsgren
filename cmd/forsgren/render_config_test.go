package main

import (
	"path/filepath"
	"strings"
	"testing"
)

const noProjectsLine = "No projects configured yet: add them to forsgren.config.yml."

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
// that says where to add them; it is the page of the golden file.
func TestRenderSaysWhenNoProjectsAreConfigured(t *testing.T) {
	code, stderr, index := renderWith(t, "--config", writeConfig(t, "version: 1\nprojects: []\n"))
	if code != 0 {
		t.Fatalf("want exit 0, got %d (stderr %q)", code, stderr)
	}
	if !strings.Contains(index, "Forsgren 0.0.6") || !strings.Contains(index, noProjectsLine) {
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

// TestRenderRefusesAnInvalidOrMissingConfig: render never publishes from a
// config check-config would refuse; it exits 1 with the same refusal, and
// writes nothing.
func TestRenderRefusesAnInvalidOrMissingConfig(t *testing.T) {
	missing := filepath.Join(t.TempDir(), "forsgren.config.yml")
	invalid := writeConfig(t, "version: 1\nprojcts: []\n")
	for name, path := range map[string]string{"missing": missing, "invalid": invalid} {
		t.Run(name, func(t *testing.T) {
			code, stderr, index := renderWith(t, "--config", path)
			if code != 1 || index != "" || !strings.HasPrefix(stderr, "render: "+path+": ") {
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
