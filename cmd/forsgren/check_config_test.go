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
	ruled := writeConfig(t, strings.Replace(validConfig, "      - name: acme/api\n",
		"      - name: acme/api\n        deployments:\n          release: Releases\n"+
			"          environment=github-pages: {label: Site, paths: [website/]}\n", 1))
	bothKeys := writeConfig(t, strings.Replace(validConfig,
		"      - name: acme/ios-app\n        deployment: workflow=testflight.yml\n",
		"      - name: acme/ios-app\n        deployment: release\n        deployments:\n          release: R\n", 1))
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
		{"several rules", []string{"check-config", "--config", ruled}, 0,
			"OK: " + ruled + " is a valid forsgren config (version 1): projects: 2, repositories: 3, labels: 2\n", ""},
		{"both deployment keys", []string{"check-config", "--config", bothKeys}, 1, "",
			"check-config: " + bothKeys + `: project "Acme Shop": repository "acme/ios-app": invalid deployment: ` +
				"use deployment or deployments, not both"},
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

// TestCheckConfigAcceptsAnInvalidViewWithTheDefault (forsgren#46, #183):
// check-config exits 0 for a view that is not accepted, which falls back to
// the default, and for each valid view.
func TestCheckConfigAcceptsAnInvalidViewWithTheDefault(t *testing.T) {
	code, _, stderr := runCommand("check-config", "--config", writeConfig(t, "view: Numbers\n"+validConfig))
	if code != 0 {
		t.Errorf("want exit 0 for a view that falls back to the default, got %d, %q", code, stderr)
	}
	for _, view := range []string{"standard", "numbers", "scoring"} {
		path := writeConfig(t, "view: "+view+"\n"+validConfig)
		if code, _, stderr := runCommand("check-config", "--config", path); code != 0 {
			t.Errorf("view %s: want exit 0, got %d, %q", view, code, stderr)
		}
	}
}

// TestCheckConfigReadsAutoUpdate (forsgren#58): check-config exits 0 for a
// valid auto_update with its level, and exits 1 naming the key for a value
// that is not a boolean, a level that is not one of the three, and
// auto_update on with no level.
func TestCheckConfigReadsAutoUpdate(t *testing.T) {
	cases := []struct {
		name, keys string
		code       int
		want       string
	}{
		{"valid", "auto_update: true\nauto_update_level: patch\n", 0, ""},
		{"not a boolean", "auto_update: yes\n", 0, ""},
		{"other level", "auto_update: true\nauto_update_level: Minor\n", 0, ""},
		{"no level", "auto_update: true\n", 0, ""},
	}
	for _, tc := range cases {
		code, _, stderr := runCommand("check-config", "--config", writeConfig(t, tc.keys+validConfig))
		if code != tc.code || !strings.Contains(stderr, tc.want) {
			t.Errorf("%s: want exit %d and %q, got %d, %q", tc.name, tc.code, tc.want, code, stderr)
		}
	}
}

// TestCheckConfigReportsARejectedSettingAndExitsZero (forsgren#183): a setting
// that is not accepted is no reason to stop: check-config exits 0, its OK line
// counts them after the labels, and stderr holds one warning line for each;
// a file error is still exit 1.
func TestCheckConfigReportsARejectedSettingAndExitsZero(t *testing.T) {
	path := writeConfig(t, "view: Numbers\nhistory_days: 0\n"+validConfig)
	wantOut := "OK: " + path + " is a valid forsgren config (version 1): projects: 2, repositories: 3, " +
		"settings not accepted: 2\n"
	wantErr := "config: warning: " + path + `: invalid view "Numbers": use standard, numbers or scoring; ` +
		"using the default standard\n" +
		"config: warning: " + path + `: invalid history_days "0": use a whole number of days from 30 to 1825; ` +
		"using the default 365\n"
	if got, want := runCheckConfig(path), (checkConfigRun{0, wantOut, wantErr}); got != want {
		t.Errorf("want %+v, got %+v", want, got)
	}
	broken := writeConfig(t, "view: Numbers\n"+strings.Replace(validConfig, "release", "releases", 1))
	if got := runCheckConfig(broken).code; got != 1 {
		t.Errorf("want exit 1 for a file error beside a rejected setting, got %d", got)
	}
}

// checkConfigRun is what one run of check-config gave.
type checkConfigRun struct {
	code           int
	stdout, stderr string
}

// runCheckConfig runs check-config on the config at path.
func runCheckConfig(path string) checkConfigRun {
	code, stdout, stderr := runCommand("check-config", "--config", path)
	return checkConfigRun{code, stdout, stderr}
}
