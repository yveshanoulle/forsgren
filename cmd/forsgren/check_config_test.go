package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const validConfig = `version: 1
projects:
  - name: Acme Shop
    repositories:
      - name: acme/api
      - name: acme/ios-app
        deployment: workflow=testflight.yml
  - name: Acme Tools
    repositories:
      - name: acme/cli
        deployment: release
`

// writeConfig writes content as a forsgren.config.yml in a fresh directory
// and returns its path.
func writeConfig(t *testing.T, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "forsgren.config.yml")
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

// TestCheckConfig drives `forsgren check-config`: exit 0 and one OK line
// with the counts on a valid file, 1 and the named refusal on an invalid or
// missing one, 2 on a usage error.
func TestCheckConfig(t *testing.T) {
	valid := writeConfig(t, validConfig)
	invalid := writeConfig(t, strings.Replace(validConfig, "release", "releases", 1))
	missing := filepath.Join(t.TempDir(), "forsgren.config.yml")
	cases := []struct {
		name   string
		args   []string
		code   int
		stdout string
		stderr string
	}{
		{"valid", []string{"check-config", "--config", valid}, 0,
			"OK: " + valid + " is a valid forsgren config (version 1): projects: 2, repositories: 3\n", ""},
		{"invalid", []string{"check-config", "--config", invalid}, 1, "",
			"check-config: " + invalid + `: project "Acme Tools": repository "acme/cli": invalid deployment "releases"`},
		{"missing file", []string{"check-config", "--config", missing}, 1, "",
			"check-config: " + missing + ": cannot read the config file"},
		{"no --config", []string{"check-config"}, 2, "", "check-config: --config <path> is required"},
		{"unknown flag", []string{"check-config", "--conf", valid}, 2, "", "flag provided but not defined: -conf"},
		{"unknown command", []string{"check"}, 2, "", "forsgren check-config --config <path>"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var stdout, stderr bytes.Buffer
			if got := run(tc.args, &stdout, &stderr); got != tc.code {
				t.Errorf("want exit %d, got %d (stderr %q)", tc.code, got, stderr.String())
			}
			if stdout.String() != tc.stdout {
				t.Errorf("want stdout %q, got %q", tc.stdout, stdout.String())
			}
			if !strings.Contains(stderr.String(), tc.stderr) {
				t.Errorf("want stderr to contain %q, got %q", tc.stderr, stderr.String())
			}
		})
	}
}
