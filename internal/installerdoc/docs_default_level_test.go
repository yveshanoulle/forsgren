package installerdoc

import (
	"regexp"
	"strings"
	"testing"
)

// TestDocsStateTheStartersDefaultLevel (forsgren#150): every
// auto_update_level the configuration reference names is the starter's
// default (it names no other), and the updating doc states what the default
// does not check.
func TestDocsStateTheStartersDefaultLevel(t *testing.T) {
	level := starterLevel(t)
	configDoc := readRepoFileAsOneLine(t, "docs/configuration.md")
	found := regexp.MustCompile(`auto_update_level: (\w+)`).FindAllStringSubmatch(configDoc, -1)
	if len(found) == 0 {
		t.Error("docs/configuration.md names no auto_update_level: the test would pass vacuously")
	}
	for _, m := range found {
		if m[1] != level {
			t.Errorf("docs/configuration.md names level %q, want the starter's %q", m[1], level)
		}
	}
	const limit = "Nothing checks a release against this installation's own data."
	if !strings.Contains(readRepoFileAsOneLine(t, "docs/updating-and-releases.md"), limit) {
		t.Errorf("docs/updating-and-releases.md does not say %q", limit)
	}
}
