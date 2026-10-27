package installerdoc

import (
	"strings"
	"testing"
)

// TestReadmeDocumentationListHasAnAgentsEntry (forsgren#504): the
// Documentation list in README.md has one Agents entry, right after
// Updating and releases, that links the installer, the upgrader and the
// deleter and says the upgrader also helps with the settings a new release
// brings, such as service folders and deployment rules.
func TestReadmeDocumentationListHasAnAgentsEntry(t *testing.T) {
	readme := readRepoFile(t, "README.md")
	_, list, ok := strings.Cut(readme, "\n## Documentation\n")
	if !ok {
		t.Fatal("README.md has no Documentation section")
	}
	list, _, _ = strings.Cut(list, "\n## ")
	lines := strings.Split(strings.TrimSpace(list), "\n")
	for i, line := range lines {
		if !strings.HasPrefix(line, "- [Agents]") {
			continue
		}
		if !strings.HasPrefix(lines[i-1], "- [Updating and releases]") {
			t.Errorf("Agents entry follows %q, want Updating and releases", lines[i-1])
		}
		wantAll(t, "Agents entry", line,
			"(agent-installer.md)", "(agent-upgrade.md)", "(agent-delete.md)",
			"settings a new release brings", "service folders", "deployment rules")
		return
	}
	t.Error("the Documentation list has no Agents entry")
}
