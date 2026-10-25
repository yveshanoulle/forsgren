package installerdoc

import (
	"strings"
	"testing"
)

// starterHistoryPage is history_page as forsgren's own starter loads it,
// written as the starter writes it (forsgren#68).
func starterHistoryPage(t *testing.T) string {
	t.Helper()
	return "history_page: " + string(loadedStarter(t).HistoryPage)
}

// TestInstallerAsksForTheHistoryPage (forsgren#68, #199, #200): step 2 asks
// question 13 with the starter's default, unlisted, says the person can put the
// page in the menu, says the page fills over several daily runs and that history_days
// up to 1825 gives more half-years, and step 9's example config writes the key
// with the answer.
func TestInstallerAsksForTheHistoryPage(t *testing.T) {
	want := starterHistoryPage(t)
	ask := asOneLine(section(t, installerFile, "Step 2."))
	_, question, found := strings.Cut(ask, "13. **The History page**")
	if !found {
		t.Fatal("agent-installer.md step 2 does not ask question 13, \"The History page\"")
	}
	for _, text := range []string{"`" + want + "`", "`unlisted` or `false`", "fills in over several daily runs",
		"`history_days`", "1825", "half-years", "set `history_page: true` to put it in the menu"} {
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

// TestInstallerProvesTwelveSettingsRows (forsgren#68, #253): the settings page
// proof lists history_page as written in the config, tbd_page as left to its
// default, true, twelve rows in all, and "Changing a setting later" names
// both keys.
func TestInstallerProvesTwelveSettingsRows(t *testing.T) {
	proof := asOneLine(section(t, installerFile, "Step 12."))
	wantAll(t, "agent-installer.md step 12", proof, "`history_page`", "Twelve rows in all",
		"`tbd_page` shows `true (not set)`")
	for _, stale := range []string{"Ten rows in all", "Eleven rows in all"} {
		if strings.Contains(proof, stale) {
			t.Errorf("agent-installer.md step 12 still says %q", stale)
		}
	}
	later := asOneLine(section(t, installerFile, "Changing a setting later"))
	wantAll(t, "agent-installer.md 'Changing a setting later'", later, "`history_page`", "`tbd_page`")
}
