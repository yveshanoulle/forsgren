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
	none := writeConfig(t, "version: 1\nprojects: []\n")
	noKey := writeConfig(t, "version: 1\n")
	labelled := writeConfig(t, strings.Replace(validConfig, "      - name: acme/api\n",
		"      - name: acme/api\n        services:\n          deploy-api: API\n          deploy-admin: ADMIN\n", 1))
	emptyLabel := writeConfig(t, validConfig+"        label: \"\"\n")
	cases := []struct {
		name   string
		args   []string
		code   int
		stdout string
		stderr string
	}{
		{"valid", []string{"check-config", "--config", valid}, 0,
			"OK: " + valid + " is a valid forsgren config (version 1): projects: 2, repositories: 3\n", ""},
		{"labelled rows", []string{"check-config", "--config", labelled}, 0,
			"OK: " + labelled + " is a valid forsgren config (version 1): projects: 2, repositories: 3, labels: 2\n", ""},
		{"empty label", []string{"check-config", "--config", emptyLabel}, 1, "",
			"check-config: " + emptyLabel + `: project "Acme Tools": repository "acme/cli": invalid label: a label is empty`},
		{"no projects yet", []string{"check-config", "--config", none}, 0,
			"OK: " + none + " is a valid forsgren config (version 1): projects: 0, repositories: 0\n", ""},
		{"projects key missing", []string{"check-config", "--config", noKey}, 1, "",
			"check-config: " + noKey + ": no projects: list at least one under the projects key, " +
				"or use projects: [] for none"},
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

// TestCheckConfigRefusesAnInvalidView (forsgren#46): check-config exits 1
// and names the key and the valid values; a valid view is OK.
func TestCheckConfigRefusesAnInvalidView(t *testing.T) {
	code, _, stderr := runCommand("check-config", "--config", writeConfig(t, "view: Numbers\n"+validConfig))
	if code != 1 || !strings.Contains(stderr, `invalid view "Numbers": use standard, numbers or scoring`) {
		t.Errorf("want exit 1 and the refusal naming the view, got %d, %q", code, stderr)
	}
	for _, view := range []string{"standard", "numbers", "scoring"} {
		path := writeConfig(t, "view: "+view+"\n"+validConfig)
		if code, _, stderr := runCommand("check-config", "--config", path); code != 0 {
			t.Errorf("view %s: want exit 0, got %d, %q", view, code, stderr)
		}
	}
}
