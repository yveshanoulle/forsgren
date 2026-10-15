package main

import (
	"path/filepath"
	"strings"
	"testing"
)

// TestRenderWarnsOnARejectedSetting (forsgren#183): a setting that is not
// accepted does not stop the render, exit 0; stderr holds one warning line for
// it, naming the file, the old refusal's text and the default in use, and a
// config that is fine prints none.
func TestRenderWarnsOnARejectedSetting(t *testing.T) {
	pinNow(t)
	cfg := writeConfig(t, "version: 1\nview: Numbers\nprojects: []\n")
	code, _, stderr := runCommand("render", "--out", filepath.Join(t.TempDir(), "site"), "--config", cfg)
	want := "config: warning: " + cfg + `: invalid view "Numbers": use standard, numbers or scoring; ` +
		"using the default standard\n"
	if code != 0 || stderr != want {
		t.Errorf("want exit 0 and stderr %q, got %d, %q", want, code, stderr)
	}
	clean := writeConfig(t, "version: 1\nprojects: []\n")
	code, _, stderr = runCommand("render", "--out", filepath.Join(t.TempDir(), "site"), "--config", clean)
	if code != 0 || stderr != "" {
		t.Errorf("want exit 0 and no stderr for a fine config, got %d, %q", code, stderr)
	}
}

// TestRenderWarningStaysOnOneLine (forsgren#183): a value with a line break or
// a control character shows escaped, so one rejected setting is one line and
// none can start a workflow command with ::.
func TestRenderWarningStaysOnOneLine(t *testing.T) {
	pinNow(t)
	cfg := writeConfig(t, "version: 1\nview: \"a\\n::error::b\\x07\"\nprojects: []\n")
	_, _, stderr := runCommand("render", "--out", filepath.Join(t.TempDir(), "site"), "--config", cfg)
	if lines := strings.Split(strings.TrimSuffix(stderr, "\n"), "\n"); len(lines) != 1 ||
		!strings.Contains(lines[0], `invalid view "a\n::error::b\a"`) {
		t.Errorf("want one warning line with the value escaped, got %q", stderr)
	}
}
