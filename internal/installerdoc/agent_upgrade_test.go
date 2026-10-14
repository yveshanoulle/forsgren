package installerdoc

import (
	"strings"
	"testing"
)

// upgraderFile is the agent upgrader, named from the repository root.
const upgraderFile = "agent-upgrade.md"

// upgraderWIP is the line the upgrader carries until 166-11.
const upgraderWIP = "Work in progress (forsgren#166): not ready to follow yet."

// wantAll reports each of wants that text does not contain.
func wantAll(t *testing.T, where, text string, wants ...string) {
	t.Helper()
	for _, want := range wants {
		if !strings.Contains(text, want) {
			t.Errorf("%s does not contain %q", where, want)
		}
	}
}

// TestUpgraderStarts (forsgren#166, step 166-1): agent-upgrade.md checks
// the login's repo and workflow scopes, asks the person for one thing, the
// address of their current report, reads that report's footer and
// settings.html, and falls back to forsgren.config.yml when the settings
// page is missing. Until 166-11 the file says it is a work in progress and
// README.md does not link it (166-11 removes the line and adds the link).
func TestUpgraderStarts(t *testing.T) {
	doc := readRepoFile(t, upgraderFile)
	wantAll(t, "step 1", asOneLine(section(t, doc, "Step 1.")),
		"gh auth status", "'repo'", "'workflow'", "address of your current forsgren report")
	wantAll(t, "step 2", asOneLine(section(t, doc, "Step 2.")),
		"settings.html", "Forsgren</a>", "exists from forsgren 0.5.0", "forsgren.config.yml")
	wantAll(t, upgraderFile, doc, upgraderWIP)
	if strings.Contains(readRepoFile(t, "README.md"), upgraderFile) {
		t.Errorf("README.md links %s before 166-11", upgraderFile)
	}
}

// TestUpgraderStep2ComparesTheTwoPins (forsgren#166, step 166-2): step 2
// reads the version and the commit of both caller pins (metrics.yml in
// forsgren.yml, auto_update.yml in forsgren-update.yml), stops when they
// differ, checks the pinned commit is the one VERSION's release points at,
// and compares the footer's version with the pin without stopping on it.
func TestUpgraderStep2ComparesTheTwoPins(t *testing.T) {
	step := asOneLine(section(t, readRepoFile(t, upgraderFile), "Step 2."))
	wantAll(t, "step 2", step,
		"auto_update.yml@",
		"the same version and the same commit",
		"gh api repos/yveshanoulle/forsgren/commits/VERSION --jq .sha",
		"differs from the pin",
		"stop and report (a half-moved pin)")
}
