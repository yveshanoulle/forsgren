package config

import (
	"strings"
	"testing"
)

// switchLines are the lines of the starter that start with prefix followed by
// the key of a switch.
func switchLines(prefix string) []string {
	var found []string
	for _, line := range starterLines() {
		for _, k := range switchKeys {
			if strings.HasPrefix(line, prefix+k.key+": ") {
				found = append(found, line)
			}
		}
	}
	return found
}

// TestStarterShowsTheSwitchesCommentedOut (forsgren#482): the starter shows
// each of the four switches as a commented line `# <key>: true  # ...`, like
// tbd_figures, and none of them uncommented: the starter uses the defaults.
func TestStarterShowsTheSwitchesCommentedOut(t *testing.T) {
	if live := switchLines(""); len(live) != 0 {
		t.Errorf("want no switch uncommented in the starter, got %q", live)
	}
	shown := strings.Join(switchLines("# "), "\n")
	for _, k := range switchKeys {
		if !strings.Contains(shown, "# "+k.key+": true  # ") {
			t.Errorf("%s: want one commented line `# %s: true  # ...`, got %q", k.key, k.key, shown)
		}
	}
}

// TestStarterSwitchLinesAreValidWhenUncommented (forsgren#482): the four lines
// uncommented, with their trailing comments, are a config check-config
// accepts with nothing rejected.
func TestStarterSwitchLinesAreValidWhenUncommented(t *testing.T) {
	var lines []string
	for _, line := range switchLines("# ") {
		lines = append(lines, strings.TrimPrefix(line, "# "))
	}
	if len(lines) != len(switchKeys) {
		t.Fatalf("want %d switch lines, got %q", len(switchKeys), lines)
	}
	got, err := parse([]byte(strings.Join(lines, "\n") + "\n" + valid))
	if err != nil {
		t.Fatal(err)
	}
	if len(got.Rejected) != 0 {
		t.Errorf("want nothing rejected, got %v", got.Rejected)
	}
}
