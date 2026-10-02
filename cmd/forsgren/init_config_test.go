package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/config"
)

// runCommand runs forsgren with args and returns its exit status, stdout and
// stderr.
func runCommand(args ...string) (int, string, string) {
	var stdout, stderr bytes.Buffer
	code := run(args, &stdout, &stderr)
	return code, stdout.String(), stderr.String()
}

// wantRun runs forsgren with args and fails the test unless it exits 0 with
// exactly stdout and nothing on stderr.
func wantRun(t *testing.T, stdout string, args ...string) {
	t.Helper()
	code, gotOut, gotErr := runCommand(args...)
	if code != 0 || gotOut != stdout || gotErr != "" {
		t.Errorf("%v: want exit 0 and stdout %q, got %d, %q, stderr %q", args, stdout, code, gotOut, gotErr)
	}
}

// readFile returns the content of path, or fails the test.
func readFile(t *testing.T, path string) string {
	t.Helper()
	got, err := os.ReadFile(filepath.Clean(path))
	if err != nil {
		t.Fatal(err)
	}
	return string(got)
}

// TestInitConfigWritesTheStarterOnce drives `forsgren init-config`: a missing
// file is created with the starter, which check-config accepts, and the
// second run keeps it. Both exit 0.
func TestInitConfigWritesTheStarterOnce(t *testing.T) {
	path := filepath.Join(t.TempDir(), "forsgren.config.yml")
	wantRun(t, "created "+path+"\n", "init-config", "--config", path)
	if got := readFile(t, path); got != config.Starter {
		t.Errorf("want the starter written, got %q", got)
	}
	wantRun(t, "OK: "+path+" is a valid forsgren config (version 1): projects: 0, repositories: 0\n",
		"check-config", "--config", path)
	wantRun(t, "kept "+path+"\n", "init-config", "--config", path)
}

// TestInitConfigKeepsAnExistingFile: whatever it holds, the file is left byte
// for byte, and the run says so and succeeds.
func TestInitConfigKeepsAnExistingFile(t *testing.T) {
	cases := map[string]string{
		"valid":   validConfig,
		"invalid": "version: 2\nprojcts: [\n",
		"empty":   "",
	}
	for name, content := range cases {
		t.Run(name, func(t *testing.T) {
			path := writeConfig(t, content)
			wantRun(t, "kept "+path+"\n", "init-config", "--config", path)
			if got := readFile(t, path); got != content {
				t.Errorf("want the file untouched, got %q", got)
			}
		})
	}
}

// TestInitConfigFailures: a real error exits 1 with `init-config: <path>: ...`
// and creates nothing.
func TestInitConfigFailures(t *testing.T) {
	dir := t.TempDir()
	typo := filepath.Join(dir, "typo", "forsgren.config.yml")
	cases := map[string]string{"directory": dir, "missing parent directory": typo}
	for name, path := range cases {
		t.Run(name, func(t *testing.T) {
			code, stdout, stderr := runCommand("init-config", "--config", path)
			if code != 1 || stdout != "" || !strings.HasPrefix(stderr, "init-config: "+path+": ") {
				t.Errorf("want exit 1 and `init-config: <path>: ...`, got %d, %q, %q", code, stdout, stderr)
			}
		})
	}
	if _, err := os.Stat(filepath.Dir(typo)); !os.IsNotExist(err) {
		t.Errorf("want the missing parent directory not created, got %v", err)
	}
}

// TestInitConfigUsageErrors: exit 2 and the reason on stderr.
func TestInitConfigUsageErrors(t *testing.T) {
	cases := []struct {
		name   string
		args   []string
		stderr string
	}{
		{"no --config", []string{"init-config"}, "init-config: --config <path> is required"},
		{"unknown flag", []string{"init-config", "--conf", "x"}, "flag provided but not defined: -conf"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			code, stdout, stderr := runCommand(tc.args...)
			if code != 2 || stdout != "" || !strings.Contains(stderr, tc.stderr) {
				t.Errorf("want exit 2 and %q, got %d, %q, %q", tc.stderr, code, stdout, stderr)
			}
		})
	}
}

// TestUsageListsEveryCommand: the usage text names all three commands.
func TestUsageListsEveryCommand(t *testing.T) {
	code, _, stderr := runCommand()
	if code != 2 {
		t.Errorf("want exit 2, got %d", code)
	}
	for _, want := range []string{
		"forsgren render --out <dir>",
		"forsgren check-config --config <path>",
		"forsgren init-config --config <path>",
	} {
		if !strings.Contains(stderr, want) {
			t.Errorf("want the usage to list %q, got %q", want, stderr)
		}
	}
}
