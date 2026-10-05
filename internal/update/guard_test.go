package update

import "testing"

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
