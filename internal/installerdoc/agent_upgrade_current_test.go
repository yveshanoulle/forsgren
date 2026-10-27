package installerdoc

import (
	"strings"
	"testing"
)

// The upgrader on an installation already at the latest release (forsgren#505,
// step 1): step 3 no longer skips the settings, and a settings-only commit
// writes what the person accepted.

// TestUpgraderStep3OffersSettingsWhenAlreadyAtLatest: step 3 sends an
// up-to-date installation through the settings of step 5, then to step 9.
func TestUpgraderStep3OffersSettingsWhenAlreadyAtLatest(t *testing.T) {
	step := upgraderSection(t, "Step 3.")
	wantAll(t, "step 3", step,
		"the installation is already the latest release",
		"skip steps 4, 6 and 7",
		"go through the settings of \"Already at the latest release\" in step 5",
		"then go to step 9")
	if strings.Contains(step, "skip steps 4 to 8") {
		t.Error("step 3 still skips steps 4 to 8")
	}
}

// TestUpgraderStep5SettingsAtLatest: step 5 names the items that do not
// depend on a version change, why the others do, the settings-only
// go-sentence, and the way straight to step 9.
func TestUpgraderStep5SettingsAtLatest(t *testing.T) {
	wantAll(t, "step 5", upgraderSection(t, "Step 5."),
		"### Already at the latest release",
		"Several accounts (item 4), Service folders (item 5) and Several ways to deploy (item 6)",
		"do not depend on a version change",
		"A waiting pull request (item 1) and the asks of the release notes (item 2) need a version change",
		"Auto-update (item 3) is asked on a move to a release",
		"ask and propose as in the items above",
		"> Reply \"go: write the settings of OWNER/REPO at LATEST in a commit of their "+
			"> own and commit the forsgren.config.yml change\" to let me commit.",
		"No pin changes.",
		"none of the three applies, or the person skips all of them: go straight to step 9",
		"then go to step 8")
}

// TestUpgraderStep8WritesSettingsInACommitOfTheirOwn: at LATEST step 8
// writes config only, reads the head again, uses its own message, and
// checks the pins did not move.
func TestUpgraderStep8WritesSettingsInACommitOfTheirOwn(t *testing.T) {
	wantAll(t, "step 8", upgraderSection(t, "Step 8."),
		"Already at the latest release: this step is the only write, in a commit of its own",
		"config only, no pin change",
		"`BRANCH` and `HEADSHA` read as in route 6b item 1 of step 6",
		"the message `forsgren: set NAMES (settings only, no pin change)`",
		"the pins in the two caller files still read `@LATESTSHA # LATEST`")
}

// TestUpgraderStep9AndTenSayTheNewPath: the cross-references name the
// settings-only path.
func TestUpgraderStep9AndTenSayTheNewPath(t *testing.T) {
	wantAll(t, "step 9", upgraderSection(t, "Step 9."),
		"Reached from step 8 (after the settings-only commit as well), or from step 5 when the installation "+
			"was already at the latest release and no setting applied or the person skipped them all "+
			"(steps 6 to 8 skipped)")
	wantAll(t, "step 10", upgraderSection(t, "Step 10."),
		"it was already at `LATEST`, with or without a settings-only commit")
}

// TestUpgraderAtLatestCannotStopEarly: the up-to-date path names its order,
// forbids stopping or removing WORK before step 9 and the report, and the
// report names the run and what the page showed.
func TestUpgraderAtLatestCannotStopEarly(t *testing.T) {
	wantAll(t, "step 3", upgraderSection(t, "Step 3."),
		"This is not the end of the upgrade. In this order: the settings items of step 5, then step 9 "+
			"(start the run with `gh workflow run` and check the published page), then step 10, the report",
		"Never say there is nothing to upgrade and stop, and never remove `WORK`, before step 10")
	wantAll(t, "step 10", upgraderSection(t, "Step 10."),
		"already at `LATEST`: the report also names the run you started in step 9 (`RUN`) "+
			"and what the published page showed")
}
