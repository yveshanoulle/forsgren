package update

import (
	"strings"
	"testing"
)

// pinOf is the pin line of a caller file for workflow, at sha and version,
// with rest after the version comment.
func pinOf(workflow, sha, version, rest string) string {
	return "    uses: yveshanoulle/forsgren/.github/workflows/" + workflow + "@" + sha + " # " + version + rest + "\n"
}

// around is a caller file with pin as its pin line.
func around(pin string) string {
	return "jobs:\n  metrics:\n    permissions:\n      contents: write\n" + pin + "    secrets: inherit\n"
}

// oldSHA is the made-up commit the fixtures are pinned to.
const oldSHA = "437c858abd71d6f33e6f714af7984de3855d8e73"

// TestRepin: the one pin line of the workflow is moved to the new commit and
// version, with its indentation and what follows the version comment kept
// and every other line left alone.
func TestRepin(t *testing.T) {
	cases := []struct {
		name    string
		content string
		to      Target
		want    string
	}{
		{"forsgren.yml", around(pinOf("metrics.yml", oldSHA, "v0.1.3", "")),
			Target{Workflow: "metrics.yml", Version: "v0.1.4", SHA: newSHA},
			around(pinOf("metrics.yml", newSHA, "v0.1.4", ""))},
		{"auto_update.yml, what follows the comment kept",
			around(pinOf("auto_update.yml", oldSHA, "v0.1.3", " (dependabot)")),
			Target{Workflow: "auto_update.yml", Version: "v0.1.4", SHA: newSHA},
			around(pinOf("auto_update.yml", newSHA, "v0.1.4", " (dependabot)"))},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, err := Repin(c.content, c.to)
			if err != nil || got != c.want {
				t.Errorf("Repin() = %q, %v, want %q", got, err, c.want)
			}
		})
	}
}

// TestRepinNamesTheWorkflowOfAFileWithNoOrManyPinLines: a file with no pin
// line of the workflow (another workflow's pin is none) or with two is an
// error naming it.
func TestRepinNamesTheWorkflowOfAFileWithNoOrManyPinLines(t *testing.T) {
	to := Target{Workflow: "metrics.yml", Version: "v0.1.4", SHA: newSHA}
	pin := pinOf("metrics.yml", oldSHA, "v0.1.3", "")
	cases := map[string]string{
		"no pin line of the workflow": around(pinOf("auto_update.yml", oldSHA, "v0.1.3", "")),
		"two pin lines":               around(pin + pin),
	}
	for name, content := range cases {
		t.Run(name, func(t *testing.T) {
			_, err := Repin(content, to)
			if err == nil || !strings.Contains(err.Error(), "metrics.yml") {
				t.Errorf("Repin() error = %v, want one naming metrics.yml", err)
			}
		})
	}
}
