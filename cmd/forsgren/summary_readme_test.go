package main

import (
	"strings"
	"testing"
)

// TestRunSummaryTellsWhatHappenedToTheReadme (forsgren#110): --readme, the
// word install-readme printed, adds one line after Setup, in the words of
// the version that wrote it; no flag and a word it does not know add none,
// as --needs-check does.
func TestRunSummaryTellsWhatHappenedToTheReadme(t *testing.T) {
	pinNow(t)
	cases := map[string]string{
		"created":   "- README: created from forsgren " + version + "'s\n",
		"replaced":  "- README: replaced with forsgren " + version + "'s\n",
		"unchanged": "- README: unchanged\n",
		"":          "",
		"banana":    "",
	}
	for word, line := range cases {
		t.Run("readme "+word, func(t *testing.T) {
			args := []string{"run-summary", "--latest", version, "--pr-check", "ok"}
			if word != "" {
				args = append(args, "--readme", word)
			}
			wantLookup(t, summaryOf(version, "up to date")+line, "", args...)
		})
	}
}

// TestRunSummaryPutsTheReadmeLineAfterSetup: the README line follows the
// Setup line, and is the last.
func TestRunSummaryPutsTheReadmeLineAfterSetup(t *testing.T) {
	pinNow(t)
	_, stdout, _ := runCommand("run-summary", "--latest", version, "--pr-check", "ok", "--needs-check", "ok",
		"--readme", "unchanged")
	tail := stdout[strings.Index(stdout, "- Setup:"):]
	want := "- Setup: in place, or the setup issue says what is missing\n- README: unchanged\n"
	if tail != want {
		t.Errorf("want the Setup line then the README line to end the summary, got %q", tail)
	}
}
