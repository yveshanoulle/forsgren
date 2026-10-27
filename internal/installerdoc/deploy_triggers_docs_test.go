package installerdoc

import "testing"

// Deploy workflows with other triggers, rules without a paths filter, and the
// page check of the last step (forsgren#509): the upgrader and the installer
// tell the person what the proposal can and cannot count.

// otherTriggers is the sentence of both documents on a deploy workflow that
// also starts on other triggers.
var otherTriggers = []string{
	"also starts on other triggers (`release`, `schedule`, `workflow_dispatch`, `workflow_run`)",
	"name them",
	"those deployments may ship none of the commits of the proposed paths",
	"counts 0 commits in that row",
	"honest, not an error",
}

// noPathsFilter is the sentence of both documents on a rule or service whose
// deployments have no paths filter.
var noPathsFilter = []string{
	"whose deployments have no paths filter",
	"a release that ships the whole program",
	"propose the folders the program is built from",
	"found from the build files",
	"`go.mod`, `cmd/` and `internal/` for Go",
	"a Dockerfile's folder",
	"show what you found and why, and ask",
	"a rule or service without `paths` shows `Per repository` for its Time to deploy per commit " +
		"and its Commits per deployment, so the person can choose",
}

// pageCheck is the sentence of both documents on reading the TBD page.
var pageCheck = []string{
	"`tbd.html`",
	"service and rule rows",
	"wait until the run's publish has finished before reading",
	"quote in the report the rows it checks and every line of the Notes it sees",
	"`Files still being read` (note 8)",
	"never say a note is absent without quoting what the page shows",
}

// TestUpgraderNamesOtherTriggersOfADeployWorkflow: step 5 items 5 and 6.
func TestUpgraderNamesOtherTriggersOfADeployWorkflow(t *testing.T) {
	step5 := upgraderSection(t, "Step 5.")
	wantAll(t, "agent-upgrade.md step 5", step5, otherTriggers...)
	wantAll(t, "agent-upgrade.md step 5", step5, noPathsFilter...)
}

// TestInstallerNamesOtherTriggersOfADeployWorkflow: step 3 item 5.
func TestInstallerNamesOtherTriggersOfADeployWorkflow(t *testing.T) {
	step3 := asOneLine(section(t, installerFile, "Step 3."))
	wantAll(t, "agent-installer.md step 3", step3, otherTriggers...)
	wantAll(t, "agent-installer.md step 3", step3, noPathsFilter...)
}

// TestInstallerQuestionsTellWhatNoPathsShows: questions 15 and 16 point to the
// proposal for a release that ships the whole program.
func TestInstallerQuestionsTellWhatNoPathsShows(t *testing.T) {
	step2 := asOneLine(section(t, installerFile, "Step 2."))
	wantAll(t, "agent-installer.md step 2", step2,
		"a release that ships the whole program has no paths filter, so you propose the folders the program is built from")
}

// TestUpgraderStep9ReadsTheTbdPage: the page check names the page, waits for
// the publish and quotes what it sees.
func TestUpgraderStep9ReadsTheTbdPage(t *testing.T) {
	wantAll(t, "agent-upgrade.md step 9", upgraderSection(t, "Step 9."),
		append(pageCheck, "`REPORTtbd.html`")...)
}

// TestInstallerStep12ReadsTheTbdPage: the same check in the first run.
func TestInstallerStep12ReadsTheTbdPage(t *testing.T) {
	wantAll(t, "agent-installer.md step 12", asOneLine(section(t, installerFile, "Step 12.")),
		append(pageCheck, "`SITEtbd.html`")...)
}
