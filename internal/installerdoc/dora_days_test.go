package installerdoc

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/config"
)

// starterDoraDays is dora_days as forsgren's own starter loads it, written as
// the starter writes it (forsgren#178).
func starterDoraDays(t *testing.T) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "forsgren.config.yml")
	if err := os.WriteFile(path, []byte(config.Starter), 0o600); err != nil {
		t.Fatal(err)
	}
	cfg, err := config.Load(path)
	if err != nil {
		t.Fatalf("want the starter to load, got %v", err)
	}
	return "dora_days: " + strconv.Itoa(cfg.DoraDays)
}

// TestInstallerAsksForTheDoraWindow (forsgren#178): step 2 asks for the window
// with the starter's default, the three values and the history_days it needs;
// step 9's example config writes it; and its history_days range is the one
// forsgren accepts.
func TestInstallerAsksForTheDoraWindow(t *testing.T) {
	want := starterDoraDays(t)
	ask := asOneLine(section(t, installerFile, "Step 2."))
	for _, text := range []string{want, "30, 90 or 180", "usually reports 180 days", "`history_days` of at least",
		"A whole number from " + strconv.Itoa(config.MinHistoryDays) + " to " + strconv.Itoa(config.MaxHistoryDays)} {
		if !strings.Contains(ask, text) {
			t.Errorf("agent-installer.md step 2 does not say %q", text)
		}
	}
	if strings.Contains(ask, "number from 1 to 1825") {
		t.Error("agent-installer.md step 2 still gives history_days the range 1 to 1825")
	}
	if write := asOneLine(section(t, installerFile, "Step 9.")); !strings.Contains(write, want) {
		t.Errorf("agent-installer.md step 9 does not write %q", want)
	}
}

// TestInstallerStep9SaysASettingNotAcceptedIsAWarning (forsgren#183, #178):
// check-config no longer fails on a setting it does not accept; it warns and
// uses the default, and the installer says what to do.
func TestInstallerStep9SaysASettingNotAcceptedIsAWarning(t *testing.T) {
	write := asOneLine(section(t, installerFile, "Step 9."))
	for _, text := range []string{"config: warning:", "settings not accepted"} {
		if !strings.Contains(write, text) {
			t.Errorf("agent-installer.md step 9 does not mention %q", text)
		}
	}
	if strings.Contains(write, "when the file is invalid") && !strings.Contains(write, "a setting") {
		t.Error("agent-installer.md step 9 still says an invalid file fails the first run without the exception for settings")
	}
}

// TestInstallerProvesTheDoraDaysRow (forsgren#178): the settings page proof
// lists dora_days as written in the config, nine rows in all, and "Changing a
// setting later" names the key.
func TestInstallerProvesTheDoraDaysRow(t *testing.T) {
	proof := asOneLine(section(t, installerFile, "Step 12."))
	for _, text := range []string{"`dora_days`", "Nine rows in all"} {
		if !strings.Contains(proof, text) {
			t.Errorf("agent-installer.md step 12 does not say %q", text)
		}
	}
	if strings.Contains(proof, "Eight rows in all") {
		t.Error("agent-installer.md step 12 still says eight rows")
	}
	if later := asOneLine(section(t, installerFile, "Changing a setting later")); !strings.Contains(later, "`dora_days`") {
		t.Error("agent-installer.md 'Changing a setting later' does not list dora_days")
	}
}

// TestUpgradeFileNamesNoDoraDays (forsgren#178): the upgrade file stays
// generic; the release notes carry the new key.
func TestUpgradeFileNamesNoDoraDays(t *testing.T) {
	if strings.Contains(readRepoFile(t, upgraderFile), "dora_days") {
		t.Error("agent-upgrade.md names dora_days; the release notes carry it")
	}
}
