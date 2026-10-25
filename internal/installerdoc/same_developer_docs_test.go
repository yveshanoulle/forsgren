package installerdoc

import (
	"strings"
	"testing"
)

// TestConfigurationSaysWhereToFindTheLoginsToGroup (forsgren#417): the
// same_developer entry tells where the logins to group are found, since the
// TBD page shows counts only, names the typical cases, and says the Mainline
// Lead Time group is the PR Lead Time (forsgren#403).
func TestConfigurationSaysWhereToFindTheLoginsToGroup(t *testing.T) {
	text := readRepoFileAsOneLine(t, "docs/configuration.md")
	wantAll(t, "docs/configuration.md", text,
		"Finding the logins to group",
		"the `author` column of `data/commits.csv`",
		"the commit list of the repository on GitHub",
		"an assistant or agent account that commits for a person",
		"one person with a work account and a private account",
		"and PR Lead Time counts pull requests, not people")
	if strings.Contains(text, "Mainline Lead Time counts pull requests") {
		t.Error("docs/configuration.md still says Mainline Lead Time counts pull requests")
	}
}

// TestInstallerAndUpgraderAskAboutSeveralAccounts (forsgren#417): the
// installer asks one question about commits from more than one GitHub
// account or an assistant account, shows the same_developer lines with the
// logins and writes them only with the person's yes; the upgrader asks the
// same where it asks the person.
func TestInstallerAndUpgraderAskAboutSeveralAccounts(t *testing.T) {
	wantAll(t, "agent-installer.md step 2", asOneLine(section(t, installerFile, "Step 2.")),
		"commit with more than one GitHub account, or through an assistant account",
		"`same_developer`",
		"only with the person's yes")
	wantAll(t, "agent-installer.md step 9", asOneLine(section(t, installerFile, "Step 9.")),
		"`same_developer`", "only when the person said yes")
	wantAll(t, "agent-upgrade.md step 5", upgraderSection(t, "Step 5."),
		"commit with more than one GitHub account, or through an assistant account",
		"`same_developer`",
		"only with the person's yes")
}

// TestManualDescribesTheTbdFiguresAndTheRefusedPushRead (forsgren#417, for
// #423 and #414): the configuration manual describes tbd_figures and its
// default, the release notes tell what 1.22.0 changes on the TBD page, and
// they have the refused push read.
func TestManualDescribesTheTbdFiguresAndTheRefusedPushRead(t *testing.T) {
	wantAll(t, "docs/configuration.md", readRepoFileAsOneLine(t, "docs/configuration.md"),
		"**`tbd_figures`** is optional",
		"`median`: the median of each measure, one column each. This is the default.",
		"`all`: the mean, the median and the 90th percentile of each measure")
	wantAll(t, "docs/updating-and-releases.md", readRepoFileAsOneLine(t, "docs/updating-and-releases.md"),
		"Upgrading to 1.22.0, which shows the median on the TBD page",
		"add `tbd_figures: all`",
		"currently no data for this project in the last 30 days",
		"**A refused push read** (forsgren#414)",
		"[--pushes-denied <path>]")
}
