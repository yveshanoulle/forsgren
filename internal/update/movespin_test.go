package update

import "testing"

// pinLines is a patch with one pin line removed and one added, each of the
// workflow and version given.
func pinLines(removedWorkflow, removedVersion, addedWorkflow, addedVersion string) string {
	const sha = "@437c858abd71d6f33e6f714af7984de3855d8e73 # "
	const uses = "    uses: yveshanoulle/forsgren/.github/workflows/"
	return "@@ -14 +14 @@\n-" + uses + removedWorkflow + sha + removedVersion + "\n" +
		"+" + uses + addedWorkflow + sha + addedVersion + "\n"
}

// TestMovesPinToFindsAPullRequestByWhatItChanges (forsgren#42): a changed file
// whose patch removes one pin line of the workflow and adds one at the wanted
// version moves the pin there; another workflow, another version, no pin, two
// pins in the patch and a pin moved back do not.
func TestMovesPinToFindsAPullRequestByWhatItChanges(t *testing.T) {
	two := pinLines("metrics.yml", "v1.8.1", "metrics.yml", "v1.8.2") +
		"-    uses: yveshanoulle/forsgren/.github/workflows/metrics.yml@437c858abd71d6f33e6f714af7984de3855d8e73 # v1.8.0\n" +
		"+    uses: yveshanoulle/forsgren/.github/workflows/metrics.yml@437c858abd71d6f33e6f714af7984de3855d8e73 # v1.8.2\n"
	tests := []struct {
		name  string
		files []File
		want  bool
	}{
		{"the pin moves to the version",
			[]File{forsgrenYML(pinLines("metrics.yml", "v1.8.1", "metrics.yml", "v1.8.2"))}, true},
		{"in the second file", []File{forsgrenYML("@@ -1 +1 @@\n-x\n+y\n"),
			forsgrenUpdateYML(pinLines("metrics.yml", "v1.8.1", "metrics.yml", "v1.8.2"))}, true},
		{"another workflow", []File{forsgrenYML(pinLines("update.yml", "v1.8.1", "update.yml", "v1.8.2"))}, false},
		{"another version", []File{forsgrenYML(pinLines("metrics.yml", "v1.8.1", "metrics.yml", "v1.8.3"))}, false},
		{"no pin", []File{forsgrenYML("@@ -1 +1 @@\n-x\n+y\n")}, false},
		{"no file", nil, false},
		{"two pins in the patch", []File{forsgrenYML(two)}, false},
		{"the pin moved back", []File{forsgrenYML(pinLines("metrics.yml", "v1.8.2", "metrics.yml", "v1.8.1"))}, false},
		{"another workflow replaced by the wanted one", []File{forsgrenYML(pinLines("update.yml", "v1.8.1",
			"metrics.yml", "v1.8.2"))}, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := MovesPinTo(tt.files, "metrics.yml", "1.8.2"); got != tt.want {
				t.Errorf("MovesPinTo(%s) = %v, want %v", tt.name, got, tt.want)
			}
		})
	}
}
