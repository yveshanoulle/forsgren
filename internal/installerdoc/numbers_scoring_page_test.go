package installerdoc

import (
	"strconv"
	"strings"
	"testing"
)

// starterNumbersScoringPage is numbers_scoring_page as forsgren's own starter
// loads it, written as the starter writes it (forsgren#55).
func starterNumbersScoringPage(t *testing.T) string {
	t.Helper()
	return "numbers_scoring_page: " + strconv.FormatBool(loadedStarter(t).NumbersScoringPage)
}

// TestInstallerAsksForTheNumbersAndScoringPage (forsgren#55): step 2 asks
// question 12 with the starter's default and says what the page shows, and
// step 9's example config writes the key with the answer.
func TestInstallerAsksForTheNumbersAndScoringPage(t *testing.T) {
	want := starterNumbersScoringPage(t)
	ask := asOneLine(section(t, installerFile, "Step 2."))
	for _, text := range []string{"12. **The Numbers and scoring page**", "`" + want + "`", "`true` or `false`",
		"number and its score"} {
		if !strings.Contains(ask, text) {
			t.Errorf("agent-installer.md step 2 does not say %q", text)
		}
	}
	write := asOneLine(section(t, installerFile, "Step 9."))
	for _, text := range []string{want, "answer to question 12"} {
		if !strings.Contains(write, text) {
			t.Errorf("agent-installer.md step 9 does not say %q", text)
		}
	}
}

// TestInstallerProvesTenSettingsRows (forsgren#55): the settings page proof
// lists numbers_scoring_page as written in the config, ten rows in all, and
// "Changing a setting later" names the key.
func TestInstallerProvesTenSettingsRows(t *testing.T) {
	proof := asOneLine(section(t, installerFile, "Step 12."))
	for _, text := range []string{"`numbers_scoring_page`", "Ten rows in all"} {
		if !strings.Contains(proof, text) {
			t.Errorf("agent-installer.md step 12 does not say %q", text)
		}
	}
	if strings.Contains(proof, "Nine rows in all") {
		t.Error("agent-installer.md step 12 still says nine rows")
	}
	later := asOneLine(section(t, installerFile, "Changing a setting later"))
	if !strings.Contains(later, "`numbers_scoring_page`") {
		t.Error("agent-installer.md 'Changing a setting later' does not list numbers_scoring_page")
	}
}
