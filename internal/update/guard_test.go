package update

import (
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/config"
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

// published is the lookup of the release v0.1.4 in these fixtures: published,
// its tag at newSHA.
var published = Release{Published: true, SHA: newSHA}

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
		name       string
		files      []File
		oldVersion string
		newVersion string
	}{
		{"dependabot bumps the pin of forsgren.yml", []File{forsgrenYML(dependabotBump)}, "v0.1.3", "v0.1.4"},
		{
			"dependabot bumps both callers to the same release",
			[]File{forsgrenYML(dependabotBump), forsgrenUpdateYML(updatePin)}, "v0.1.3", "v0.1.4",
		},
		{
			"v0.1.10 is newer than v0.1.9, the parts compared as numbers",
			[]File{forsgrenYML(versionedPin("v0.1.9", "v0.1.10"))}, "v0.1.9", "v0.1.10",
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			want := Decision{Merge: true, Old: c.oldVersion, New: c.newVersion, NewSHA: newSHA}
			got := Decide(Pull{Author: "dependabot[bot]", Files: c.files, Release: published, Level: config.LevelPatch})
			if got != want {
				t.Errorf("Decide() = %+v, want %+v", got, want)
			}
		})
	}
}

// TestDecideMergesAnUpdateWithinTheLevel pins forsgren#58: an update may go
// as far as auto_update_level allows. At patch only the patch number moves;
// at minor the minor or the patch number moves with the major unchanged; at
// major anything moves.
func TestDecideMergesAnUpdateWithinTheLevel(t *testing.T) {
	cases := []struct {
		name       string
		level      string
		oldVersion string
		newVersion string
	}{
		{"a patch update at patch", config.LevelPatch, "v0.1.3", "v0.1.4"},
		{"a minor update at minor", config.LevelMinor, "v0.1.4", "v0.2.0"},
		{"a major update at major", config.LevelMajor, "v0.4.0", "v1.0.0"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			want := Decision{Merge: true, Old: c.oldVersion, New: c.newVersion, NewSHA: newSHA}
			files := []File{forsgrenYML(versionedPin(c.oldVersion, c.newVersion))}
			got := Decide(Pull{Author: "dependabot[bot]", Files: files, Release: published, Level: c.level})
			if got != want {
				t.Errorf("Decide() = %+v, want %+v", got, want)
			}
		})
	}
}

// TestDecideLeavesAnUpdateBeyondTheLevelForAHuman pins forsgren#58: a minor
// or major update beyond auto_update_level is left for a human with a reason
// naming the update and the level, and so is an empty level, which the
// config never allows with auto_update on and the guard never merges on.
func TestDecideLeavesAnUpdateBeyondTheLevelForAHuman(t *testing.T) {
	cases := []struct {
		name       string
		level      string
		oldVersion string
		newVersion string
		reason     string
	}{
		{
			"a minor update at patch", config.LevelPatch, "v0.1.4", "v0.2.0",
			"v0.1.4 to v0.2.0 is a minor update; auto_update_level is patch",
		},
		{
			"a major update at patch", config.LevelPatch, "v0.4.0", "v1.0.0",
			"v0.4.0 to v1.0.0 is a major update; auto_update_level is patch",
		},
		{
			"a major update at minor", config.LevelMinor, "v0.4.0", "v1.0.0",
			"v0.4.0 to v1.0.0 is a major update; auto_update_level is minor",
		},
		{"no level", "", "v0.1.3", "v0.1.4", "no auto_update_level"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			files := []File{forsgrenYML(versionedPin(c.oldVersion, c.newVersion))}
			got := Decide(Pull{Author: "dependabot[bot]", Files: files, Release: published, Level: c.level})
			if got.Merge || !strings.Contains(got.Reason, c.reason) {
				t.Errorf("Decide() = %+v, want left with a reason containing %q", got, c.reason)
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

// versionedPin is a hunk of a removed pin line of metrics.yml at oldVersion
// and an added one at newVersion, as they would be written in a patch of
// forsgren.yml.
func versionedPin(oldVersion, newVersion string) string {
	return "@@ -14 +14 @@\n" +
		"-    uses: yveshanoulle/forsgren/.github/workflows/metrics.yml" +
		"@437c858abd71d6f33e6f714af7984de3855d8e73 # " + oldVersion + "\n" +
		"+    uses: yveshanoulle/forsgren/.github/workflows/metrics.yml" +
		"@" + newSHA + " # " + newVersion + "\n"
}

// TestDecideLeavesAPinWhoseVersionIsNoReleaseForAHuman pins forsgren#58: the
// version comment of a pin, removed or added, is a release version, v and
// three numbers, and any other text is left for a human with a reason that
// quotes it.
func TestDecideLeavesAPinWhoseVersionIsNoReleaseForAHuman(t *testing.T) {
	cases := []struct {
		name       string
		oldVersion string
		newVersion string
		reason     string
	}{
		{"added version with two numbers", "v0.2.3", "v0.4", "v0.4"},
		{"added version without v", "v0.2.3", "0.4.5", "0.4.5"},
		{"added pre-release version", "v0.2.3", "v0.4.5-rc1", "v0.4.5-rc1"},
		{"added branch name", "v0.2.3", "latest", "latest"},
		{"removed version with two numbers", "v0.2", "v0.4.5", "v0.2"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			files := []File{forsgrenYML(versionedPin(c.oldVersion, c.newVersion))}
			got := Decide(Pull{Author: "dependabot[bot]", Files: files})
			if got.Merge || !strings.Contains(got.Reason, c.reason) {
				t.Errorf("Decide() = %+v, want left with a reason containing %q", got, c.reason)
			}
		})
	}
}

// TestDecideLeavesAVersionThatIsNoUpgradeForAHuman pins forsgren#58: the new
// version must be newer than the old one, so a downgrade and the same version
// are left for a human with a reason quoting both versions. The release is
// published and tagged at the pin, so only the versions decide.
func TestDecideLeavesAVersionThatIsNoUpgradeForAHuman(t *testing.T) {
	cases := []struct {
		name       string
		oldVersion string
		newVersion string
		reason     string
	}{
		{"a downgrade", "v0.1.4", "v0.1.3", "v0.1.4 to v0.1.3"},
		{"the same version at another commit", "v0.1.4", "v0.1.4", "v0.1.4 to v0.1.4"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			files := []File{forsgrenYML(versionedPin(c.oldVersion, c.newVersion))}
			got := Decide(Pull{Author: "dependabot[bot]", Files: files, Release: published})
			if got.Merge || !strings.Contains(got.Reason, c.reason) {
				t.Errorf("Decide() = %+v, want left with a reason containing %q", got, c.reason)
			}
		})
	}
}

// TestDecideLeavesAVersionWithoutAPublishedReleaseAtThePinForAHuman pins
// forsgren#58: the new version must be a published release of forsgren whose
// tag points at the pinned commit. A version with no published release is
// left with a reason quoting the version, and a tag that points at another
// commit with a reason quoting that commit.
func TestDecideLeavesAVersionWithoutAPublishedReleaseAtThePinForAHuman(t *testing.T) {
	tagSHA := "fedcba9876543210fedcba9876543210fedcba98"
	cases := []struct {
		name    string
		release Release
		reason  string
	}{
		{"no published release", Release{}, "v0.1.4"},
		{"a tag of another commit", Release{Published: true, SHA: tagSHA}, tagSHA},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			files := []File{forsgrenYML(dependabotBump)}
			got := Decide(Pull{Author: "dependabot[bot]", Files: files, Release: c.release, Level: config.LevelPatch})
			if got.Merge || !strings.Contains(got.Reason, c.reason) {
				t.Errorf("Decide() = %+v, want left with a reason containing %q", got, c.reason)
			}
		})
	}
}

// TestDecideLeavesAPullRequestOfAnyOtherAuthorForAHuman pins forsgren#58:
// only the author dependabot[bot], spelled exactly so, may have its pull
// request merged; any other author, a person, a login without [bot], another
// case or none, is left for a human with a reason that names the author.
func TestDecideLeavesAPullRequestOfAnyOtherAuthorForAHuman(t *testing.T) {
	cases := []struct {
		name   string
		author string
		reason string
	}{
		{"a person", "octo-person", "octo-person"},
		{"dependabot without [bot]", "dependabot", "dependabot"},
		{"dependabot in another case", "Dependabot[bot]", "Dependabot[bot]"},
		{"no author", "", "author"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := Decide(Pull{Author: c.author, Files: []File{forsgrenYML(dependabotBump)}})
			if got.Merge || !strings.Contains(got.Reason, c.reason) {
				t.Errorf("Decide() = %+v, want left with a reason containing %q", got, c.reason)
			}
		})
	}
}

// TestNewVersionIsTheVersionOfTheAddedPin: the version the pull request moves
// the pin to, read from the first file that adds a pin line; false when no
// file does.
func TestNewVersionIsTheVersionOfTheAddedPin(t *testing.T) {
	got, ok := NewVersion([]File{forsgrenYML("@@ -1 +1 @@\n-x\n+y\n"), forsgrenYML(dependabotBump)})
	if !ok || got != "v0.1.4" {
		t.Errorf("NewVersion() = %q, %v, want v0.1.4, true", got, ok)
	}
	if got, ok := NewVersion([]File{forsgrenYML("@@ -1 +1 @@\n-x\n+y\n")}); ok || got != "" {
		t.Errorf("NewVersion() without a pin = %q, %v, want empty, false", got, ok)
	}
}
