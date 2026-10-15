package main

import (
	"fmt"
	"os"
	"slices"
	"strings"
	"testing"
)

// usageDiff compares the usage text with the fenced block of doc that starts
// with its first line, and says what differs: "" when the block holds the
// usage byte for byte (forsgren#193).
func usageDiff(doc string) string {
	block, found := fencedBlockStarting(strings.Split(doc, "\n"), strings.Split(usage, "\n")[0])
	if !found {
		return "no fenced block starts with the first line of the usage"
	}
	want := strings.Split(usage, "\n")
	for n := 0; n < max(len(block), len(want)); n++ {
		if at(block, n) != at(want, n) {
			return fmt.Sprintf("line %d of the block: the doc has %q, the usage has %q", n+1, at(block, n), at(want, n))
		}
	}
	return ""
}

// fencedBlockStarting is the lines of the fenced block of lines whose first
// line is first, up to its closing fence, and whether there is one.
func fencedBlockStarting(lines []string, first string) ([]string, bool) {
	start := slices.Index(lines, first)
	if start < 1 || lines[start-1] != "```" {
		return nil, false
	}
	end := slices.Index(lines[start:], "```")
	if end < 0 {
		return lines[start:], true
	}
	return lines[start : start+end], true
}

// at is lines[n], or "" past the end.
func at(lines []string, n int) string {
	if n < len(lines) {
		return lines[n]
	}
	return ""
}

// TestUsageDiffNamesWhatDiffers shows the comparison seeing a doc that lost a
// flag, one that lost the block and one that is exact.
func TestUsageDiffNamesWhatDiffers(t *testing.T) {
	exact := "intro\n\n```\n" + usage + "\n```\n\nafter\n"
	if got := usageDiff(exact); got != "" {
		t.Errorf("an exact copy differs: %s", got)
	}
	lost := strings.Replace(exact, " [--needs-check <status>]", "", 1)
	if got := usageDiff(lost); !strings.Contains(got, "line 2") || !strings.Contains(got, "--needs-check") {
		t.Errorf("a copy without one flag: want the differing line named, got %q", got)
	}
	if got := usageDiff("no block here\n"); !strings.Contains(got, "no fenced block") {
		t.Errorf("a doc without the block: want that said, got %q", got)
	}
}

// TestConfigurationDocHoldsTheUsageText keeps the usage block of
// docs/configuration.md equal to the text forsgren prints.
func TestConfigurationDocHoldsTheUsageText(t *testing.T) {
	doc, err := os.ReadFile("../../docs/configuration.md")
	if err != nil {
		t.Fatal(err)
	}
	if got := usageDiff(string(doc)); got != "" {
		t.Errorf("docs/configuration.md and the printed usage differ: %s", got)
	}
}
