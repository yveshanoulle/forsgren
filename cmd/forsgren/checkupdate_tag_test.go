package main

import (
	"slices"
	"testing"
)

// TestCheckUpdateLooksUpTheReleaseOfTheNewVersionNotTheOldOne: the release
// asked for is the one of the version the pin moves to. The old version
// v0.1.3 has a published release whose tag is at the old pinned commit, the
// new version v0.1.4 has none, so the pull request is left for a human for
// want of v0.1.4's release; v0.1.3's release is never asked for.
func TestCheckUpdateLooksUpTheReleaseOfTheNewVersionNotTheOldOne(t *testing.T) {
	answers := mergeableAnswers(t)
	answers[releasePath] = answer{404, `{"message":"Not Found"}`}
	answers["/repos/yveshanoulle/forsgren/releases/tags/v0.1.3"] = answer{200, `{"tag_name": "v0.1.3"}`}
	answers["/repos/yveshanoulle/forsgren/commits/tags/v0.1.3"] = answer{200, oldPinSHA}
	asked := recordedAPI(t, answers)
	got := checkUpdateRun(argsOf(updateFlags(t), "config", "repo", "pull")...)
	wantLeft(t, got, "v0.1.4 is no published release of forsgren")
	if paths := asked(); !slices.Contains(paths, releasePath) {
		t.Errorf("want the release of v0.1.4 asked for, got %v", paths)
	}
	for _, path := range asked() {
		if path == "/repos/yveshanoulle/forsgren/releases/tags/v0.1.3" {
			t.Errorf("want the release of the old version never asked for, got %v", asked())
		}
	}
}
