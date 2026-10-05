package main

import "testing"

// TestCheckUpdateLeavesEverythingForAHumanWhileAutoUpdateIsOff: an installation
// that has not turned auto_update on (the key absent, or false, with or
// without a level) is never asked of GitHub: the one line is `left for a
// human: auto_update is off`, the exit status 1, and no request is made, even
// for a pull request the guard would merge.
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
