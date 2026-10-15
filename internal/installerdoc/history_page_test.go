package installerdoc

import (
	"strconv"
	"strings"
	"testing"
)

// starterHistoryPage is history_page as forsgren's own starter loads it,
// written as the starter writes it (forsgren#68).
func starterHistoryPage(t *testing.T) string {
	t.Helper()
	return "history_page: " + strconv.FormatBool(loadedStarter(t).HistoryPage)
}

// TestInstallerAsksForTheHistoryPage (forsgren#68): step 2 asks question 13
// with the starter's default, says the page fills over several daily runs and
// that history_days up to 1825 gives more half-years, and step 9's example
// config writes the key with the answer.
func TestInstallerAsksForTheHistoryPage(t *testing.T) {
	want := starterHistoryPage(t)
	ask := asOneLine(section(t, installerFile, "Step 2."))
	_, question, found := strings.Cut(ask, "13. **The History page**")
	if !found {
		t.Fatal("agent-installer.md step 2 does not ask question 13, \"The History page\"")
	}
	for _, text := range []string{"`" + want + "`", "`true` or `false`", "fills in over several daily runs",
		"`history_days`", "1825", "half-years"} {
		if !strings.Contains(question, text) {
			t.Errorf("agent-installer.md question 13 does not say %q", text)
		}
	}
	write := asOneLine(section(t, installerFile, "Step 9."))
	for _, text := range []string{want, "answer to question 13"} {
		if !strings.Contains(write, text) {
			t.Errorf("agent-installer.md step 9 does not say %q", text)
		}
	}
}

// TestInstallerProvesElevenSettingsRows (forsgren#68): the settings page proof
// lists history_page as written in the config, eleven rows in all, and
// "Changing a setting later" names the key.
func TestInstallerProvesElevenSettingsRows(t *testing.T) {
	proof := asOneLine(section(t, installerFile, "Step 12."))
	for _, text := range []string{"`history_page`", "Eleven rows in all"} {
		if !strings.Contains(proof, text) {
			t.Errorf("agent-installer.md step 12 does not say %q", text)
		}
	}
	if strings.Contains(proof, "Ten rows in all") {
		t.Error("agent-installer.md step 12 still says ten rows")
	}
	later := asOneLine(section(t, installerFile, "Changing a setting later"))
	if !strings.Contains(later, "`history_page`") {
		t.Error("agent-installer.md 'Changing a setting later' does not list history_page")
	}
}
