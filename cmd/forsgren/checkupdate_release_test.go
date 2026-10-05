package main

import "testing"

// Paths of the release of v0.1.4 and of its tag's commit, on forsgren's own
// repository, which check-update looks the new version up on.
const (
	releasePath   = "/repos/yveshanoulle/forsgren/releases/tags/v0.1.4"
	tagCommitPath = "/repos/yveshanoulle/forsgren/commits/tags/v0.1.4"
)

// otherSHA is a made-up commit that the pin is not at.
const otherSHA = "89abcdef0123456789abcdef0123456789abcdef"

// TestCheckUpdateLeavesAVersionWithNoPublishedReleaseForAHuman: a release
// that GitHub answers with 404, or with 200 and draft: true (what a token
// that may push sees of a draft), is no published release: the reason names
// the version, the exit status is 1, and the tag's commit, which a 404
// release has none of, is not needed.
func TestCheckUpdateLeavesAVersionWithNoPublishedReleaseForAHuman(t *testing.T) {
	notPublished := map[string]answer{
		"a 404":   {404, `{"message":"Not Found"}`},
		"a draft": {200, `{"tag_name": "v0.1.4", "draft": true}`},
	}
	for name, release := range notPublished {
		t.Run(name, func(t *testing.T) {
			answers := mergeableAnswers(t)
			answers[releasePath] = release
			answers[tagCommitPath] = answer{404, `{"message":"Not Found"}`}
			recordedAPI(t, answers)
			got := checkUpdateRun(argsOf(updateFlags(t), "config", "repo", "pull")...)
			wantLeft(t, got, "v0.1.4 is no published release of forsgren")
		})
	}
}

// TestCheckUpdateLeavesATagAtAnotherCommitForAHuman: a published release
// whose tag points at a commit other than the pinned one is named with both
// commits.
func TestCheckUpdateLeavesATagAtAnotherCommitForAHuman(t *testing.T) {
	answers := mergeableAnswers(t)
	answers[tagCommitPath] = answer{200, otherSHA}
	recordedAPI(t, answers)
	got := checkUpdateRun(argsOf(updateFlags(t), "config", "repo", "pull")...)
	wantLeft(t, got, "the tag v0.1.4 points at "+otherSHA+", not at the pinned "+newPinSHA)
}
