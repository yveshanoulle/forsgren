package main

import "testing"

// TestCollectWarnsOnARejectedSetting (forsgren#183): a setting that is not
// accepted does not stop collect, exit 0; stderr holds the one warning line for
// it, as render prints it.
func TestCollectWarnsOnARejectedSetting(t *testing.T) {
	t.Setenv("FORSGREN_TOKEN", "")
	cfg := writeConfig(t, "version: 1\nhistory_days: 0\nprojects: []\n")
	got := collectRun("--config", cfg, "--data", dataPath(t))
	want := "config: warning: " + cfg + `: invalid history_days "0": use a whole number of days from 30 to 1825; ` +
		"using the default 365\n"
	if got.code != 0 || got.stdout != "" || got.stderr != want {
		t.Errorf("want exit 0, no stdout and stderr %q, got %+v", want, got)
	}
}
