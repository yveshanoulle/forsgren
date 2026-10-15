package main

import "testing"

// TestCheckUpdateLeavesEverythingForAHumanWhileAutoUpdateIsOff: an installation
// that has not turned auto_update on (the key absent, or false, with or
// without a level) is never asked of GitHub: the one line is `left for a human:
// auto_update is off`, the exit status 1, and no request is made, even for a
// pull request the guard would merge.
func TestCheckUpdateLeavesEverythingForAHumanWhileAutoUpdateIsOff(t *testing.T) {
	configs := map[string]string{
		"the key absent":             oneRepository,
		"false":                      oneRepository + "auto_update: false\n",
		"false with a level written": oneRepository + "auto_update: false\nauto_update_level: patch\n",
	}
	for name, content := range configs {
		t.Run(name, func(t *testing.T) {
			asked := recordedAPI(t, mergeableAnswers(t))
			flags := updateFlags(t)
			flags["config"] = configFile(t, content)
			got := checkUpdateRun(argsOf(flags, "config", "repo", "pull")...)
			wantLeft(t, got, "auto_update is off")
			if paths := asked(); len(paths) != 0 {
				t.Errorf("want no request, got %v", paths)
			}
		})
	}
}

// TestCheckUpdateWarnsOnARejectedSetting (forsgren#183): an auto_update that is
// not accepted falls back to off, so the pull request is left for a human,
// exit 1 and no request, and stderr holds the one warning line for it.
func TestCheckUpdateWarnsOnARejectedSetting(t *testing.T) {
	asked := recordedAPI(t, mergeableAnswers(t))
	flags := updateFlags(t)
	flags["config"] = configFile(t, oneRepository+"auto_update: yes\nauto_update_level: patch\n")
	got := checkUpdateRun(argsOf(flags, "config", "repo", "pull")...)
	want := outcome{code: 1, stdout: "left for a human: auto_update is off\n",
		stderr: "config: warning: " + flags["config"] + `: invalid auto_update "yes": use true or false; ` +
			"using the default false\n"}
	if got != want {
		t.Errorf("want %+v, got %+v", want, got)
	}
	if paths := asked(); len(paths) != 0 {
		t.Errorf("want no request, got %v", paths)
	}
}
