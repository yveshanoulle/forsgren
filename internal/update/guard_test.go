package update

import (
	"strings"
	"testing"
)

// newSHA is the made-up commit of the release v0.1.4 in these fixtures.
const newSHA = "0123456789abcdef0123456789abcdef01234567"

// dependabotBump is the patch of Dependabot's bump of the pin in the data
// repository's forsgren.yml: the old line removed, the new line added, the
// new sha made up. It is the shape GitHub's pull request files answer has.
const dependabotBump = "@@ -14,7 +14,7 @@ jobs:\n" +
	"   metrics:\n" +
	"     permissions:\n" +
	"       contents: write\n" +
	"-    uses: yveshanoulle/forsgren/.github/workflows/metrics.yml" +
	"@437c858abd71d6f33e6f714af7984de3855d8e73 # v0.1.3\n" +
	"+    uses: yveshanoulle/forsgren/.github/workflows/metrics.yml" +
	"@" + newSHA + " # v0.1.4\n" +
	"     secrets: inherit\n"

// forsgrenYML is the changed-file entry of the data repository's workflow
// with the given patch.
func forsgrenYML(patch string) File {
	return File{Filename: ".github/workflows/forsgren.yml", Patch: patch}
}

// forsgrenUpdateYML is the changed-file entry of the data repository's
// caller of the update workflow with the given patch.
func forsgrenUpdateYML(patch string) File {
	return File{Filename: ".github/workflows/forsgren-update.yml", Patch: patch}
}

// pinPair is a hunk of a removed pin line of oldFile at v0.1.3 and an added
// pin line of newFile at the given version and sha, both workflow files of
// forsgren.
func pinPair(oldFile, newFile, version, sha string) string {
	return "@@ -14 +14 @@\n" +
		"-    uses: yveshanoulle/forsgren/.github/workflows/" + oldFile +
		"@437c858abd71d6f33e6f714af7984de3855d8e73 # v0.1.3\n" +
		"+    uses: yveshanoulle/forsgren/.github/workflows/" + newFile +
		"@" + sha + " # " + version + "\n"
}

// TestDecideMergesADiffOfOnlyThePinLine pins forsgren#58: the pin
// line alone, old to new, may be merged, and the guard reports the versions
// and the sha it saw. A release moves the pins of both callers in one pull
// request, to the same version and sha.
func TestDecideMergesADiffOfOnlyThePinLine(t *testing.T) {
	updatePin := pinPair("auto_update.yml", "auto_update.yml", "v0.1.4", newSHA)
	cases := []struct {
		name  string
		files []File
	}{
		{"dependabot bumps the pin of forsgren.yml", []File{forsgrenYML(dependabotBump)}},
		{
			"dependabot bumps both callers to the same release",
			[]File{forsgrenYML(dependabotBump), forsgrenUpdateYML(updatePin)},
		},
	}
	want := Decision{Merge: true, Old: "v0.1.3", New: "v0.1.4", NewSHA: newSHA}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := Decide(Pull{Author: "dependabot[bot]", Files: c.files})
			if got.Merge != want.Merge || got.Old != want.Old ||
				got.New != want.New || got.NewSHA != want.NewSHA {
				t.Errorf("Decide() = %+v, want %+v", got, want)
			}
		})
	}
}

// TestDecideLeavesAnythingBesidesThePinLineForAHuman pins forsgren#58: a
// second changed file, a second changed line that is no pin line, no pin line
// at all and a second pin pair are each left for a human with one reason
// line naming what else changed. A file is judged by its name, a line by its
// text. forsgren.yml pins metrics.yml and forsgren-update.yml pins
// auto_update.yml, and a release moves both pins to the same version and
// sha; a pin of another workflow file, a pin that moves to another workflow
// file and callers that move to different releases are left.
func TestDecideLeavesAnythingBesidesThePinLineForAHuman(t *testing.T) {
	otherSHA := "fedcba9876543210fedcba9876543210fedcba98"
	pairTwice := dependabotBump + pinPair("metrics.yml", "metrics.yml", "v0.1.4", newSHA)
	cases := []struct {
		name   string
		files  []File
		reason string
	}{
		{
			name:   "a second changed file",
			files:  []File{forsgrenYML(dependabotBump), {Filename: "README.md", Patch: "@@ -1 +1 @@\n-a\n+b\n"}},
			reason: "README.md",
		},
		{
			name: "a second changed line that is no pin line",
			files: []File{forsgrenYML(dependabotBump +
				"-    - cron: '17 5 * * *'\n+    - cron: '17 6 * * *'\n")},
			reason: "cron: '17 6 * * *'",
		},
		{name: "no pin line changed", reason: "no pin line changed"},
		{
			name:   "a second pin pair",
			files:  []File{forsgrenYML(pairTwice)},
			reason: "more than one pin line",
		},
		{
			name:   "a pin of another workflow file of forsgren",
			files:  []File{forsgrenYML(pinPair("other.yml", "other.yml", "v0.1.4", newSHA))},
			reason: "other.yml",
		},
		{
			name:   "a pin of metrics.yml that moves to the update workflow",
			files:  []File{forsgrenYML(pinPair("metrics.yml", "auto_update.yml", "v0.1.4", newSHA))},
			reason: "auto_update.yml",
		},
		{
			name: "both callers bumped to different releases",
			files: []File{
				forsgrenYML(dependabotBump),
				forsgrenUpdateYML(pinPair("auto_update.yml", "auto_update.yml", "v0.1.5", otherSHA)),
			},
			reason: "v0.1.5",
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := Decide(Pull{Author: "dependabot[bot]", Files: c.files})
			if got.Merge || !strings.Contains(got.Reason, c.reason) {
				t.Errorf("Decide() = %+v, want left with a reason containing %q", got, c.reason)
			}
		})
	}
}
