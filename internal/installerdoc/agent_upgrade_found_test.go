package installerdoc

import "testing"

// The first real upgrade of 1.26.8 (forsgren#520 to #523) found four gaps in
// how the agents ask, report and keep their files.

// TestAgentsAskAboutEveryItemAnAnswerLeavesOpen (forsgren#522): an answer
// that names some items of a question with several items leaves the others
// open; the agent asks about those and never takes their default silently.
func TestAgentsAskAboutEveryItemAnAnswerLeavesOpen(t *testing.T) {
	want := "An answer that names some items of a question with several items " +
		"leaves the other items open: ask about those, and never take their default silently."
	wantAll(t, "agent-upgrade.md step 5", upgraderSection(t, "Step 5."), want)
	wantAll(t, "agent-installer.md step 2", asOneLine(section(t, installerFile, "Step 2.")), want)
}

// TestUpgraderStep9NamesTheColumnsThatChangeWithPaths (forsgren#520): three
// columns change with paths; the other `Per repository` cells of a service or
// rule row are by design.
func TestUpgraderStep9NamesTheColumnsThatChangeWithPaths(t *testing.T) {
	wantAll(t, "agent-upgrade.md step 9", upgraderSection(t, "Step 9."),
		"Three columns change with `paths`: Time to deploy per commit, Deployed commits and Commits per deployment.",
		"The other `Per repository` cells of a service or rule row are by design",
		"a row with `paths` works when those three show figures or note 8")
}

// TestAgentsKeepEveryFileInTheirWorkFolder (forsgren#521): every file the
// agent writes goes inside `WORK`, so removing it leaves nothing behind.
func TestAgentsKeepEveryFileInTheirWorkFolder(t *testing.T) {
	want := "Every file you write goes inside `WORK`, never beside it " +
		"(a list of repositories included), so removing `WORK` at the end leaves nothing behind."
	wantAll(t, "agent-upgrade.md step 2", upgraderSection(t, "Step 2."), want)
	wantAll(t, "agent-installer.md step 8", asOneLine(section(t, installerFile, "Step 8.")), want)
}

// TestUpgraderReadsTheWorkflowBehindEachRule (forsgren#523): the step that
// proposes rules reads the workflow behind each rule it proposes or keeps
// before proposing, proposes its folders, and may not skip the read.
func TestUpgraderReadsTheWorkflowBehindEachRule(t *testing.T) {
	wantAll(t, "agent-upgrade.md step 5", upgraderSection(t, "Step 5."),
		"Read the workflow behind each rule you propose or keep before you propose it "+
			"(for a `release` rule, the workflow that publishes the release), and propose its folders. "+
			"Never skip the read, never say you have not read it")
}
