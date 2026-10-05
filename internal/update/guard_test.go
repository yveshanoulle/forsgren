package update

import (
	"strings"
	"testing"
)

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
	"@0123456789abcdef0123456789abcdef01234567 # v0.1.4\n" +
	"     secrets: inherit\n"

// TestDecideMergesADiffOfOnlyThePinLine pins forsgren#58: the pin
// line alone, old to new, may be merged, and the guard reports the versions
// and the sha it saw.
func TestDecideMergesADiffOfOnlyThePinLine(t *testing.T) {
	cases := []struct {
		name string
		pull Pull
		want Decision
	}{
		{
			name: "dependabot bumps the pin of forsgren.yml",
			pull: Pull{
				Author: "dependabot[bot]",
				Files:  []File{{Filename: ".github/workflows/forsgren.yml", Patch: dependabotBump}},
			},
			want: Decision{
				Merge: true, Old: "v0.1.3", New: "v0.1.4",
				NewSHA: "0123456789abcdef0123456789abcdef01234567",
			},
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := Decide(c.pull)
			if got.Merge != c.want.Merge || got.Old != c.want.Old ||
				got.New != c.want.New || got.NewSHA != c.want.NewSHA {
				t.Errorf("Decide() = %+v, want %+v", got, c.want)
			}
		})
	}
}

// forsgrenYML is the changed-file entry of the data repository's workflow
// with the given patch.
func forsgrenYML(patch string) File {
	return File{Filename: ".github/workflows/forsgren.yml", Patch: patch}
}

// secondPin is a second removed and added pin line, of another workflow file
// of forsgren, as it would follow the lines of dependabotBump in one patch.
const secondPin = "-    uses: yveshanoulle/forsgren/.github/workflows/other.yml" +
	"@437c858abd71d6f33e6f714af7984de3855d8e73 # v0.1.3\n" +
	"+    uses: yveshanoulle/forsgren/.github/workflows/other.yml" +
	"@0123456789abcdef0123456789abcdef01234567 # v0.1.4\n"

// TestDecideLeavesAnythingBesidesThePinLineForAHuman pins forsgren#58: a
// second changed file, a second changed line that is no pin line, no pin line
// at all and a second pin pair are each left for a human with one reason
// line naming what else changed. A file is judged by its name, a line by its
// text.
func TestDecideLeavesAnythingBesidesThePinLineForAHuman(t *testing.T) {
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
			files:  []File{forsgrenYML(dependabotBump + secondPin)},
			reason: "more than one pin line",
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
