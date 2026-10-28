package installerdoc

import "testing"

// Several ways to deploy is never skipped without looking (forsgren#508): a
// repository with a `deployment:` line is exactly the case, and "only one way
// is in use" is decided from the output of the read-only commands.

// TestUpgraderItem6IsForARepositoryWithADeploymentLine: item 6 says first who
// it is for, then that the three commands run first and each is described.
func TestUpgraderItem6IsForARepositoryWithADeploymentLine(t *testing.T) {
	wantAll(t, "agent-upgrade.md step 5", upgraderSection(t, "Step 5."),
		"for every repository with a `deployment:` line, with none (the default rule), "+
			"or with a `deployments:` map that has a rule or service without `paths`",
		"a `deployment:` line does not exclude it",
		"Skip a repository only when every rule and every service already has `paths`",
		"Always run the three commands first and say what each showed",
		"only from that output decide whether only one way is in use")
}

// TestInstallerLooksAtEveryRepositoryForDeployments: question 16 and step 3
// say the same for a repository that has a `deployment:` line.
func TestInstallerLooksAtEveryRepositoryForDeployments(t *testing.T) {
	wantAll(t, "agent-installer.md question 16", asOneLine(section(t, installerFile, "Step 2.")),
		"a `deployment:` line does not exclude it",
		"Always run the commands of step 3 first and say what each showed")
	wantAll(t, "agent-installer.md step 3", asOneLine(section(t, installerFile, "Step 3.")),
		"every repository, also one with a `deployment:` line",
		"a `deployment:` line does not exclude it",
		"Always run the commands first and say what each showed",
		"only from that output decide whether only one way is in use")
}

// handOffSentences are what an agent file says when a deploy workflow only
// hands the change to a system outside GitHub: the boundary, the link to the
// hand-off page and the question (forsgren#559).
var handOffSentences = []string{
	"ends by handing the change to a system outside GitHub",
	"the change is not live when the run ends), say so",
	"`workflow=` counts the hand-off, not the moment users have the change",
	"recording a GitHub Deployment from outside (Route A or B of " +
		"[Hand-off pipelines](docs/hand-off-pipelines.md)) counts the moment they choose, such as received or synced",
	"Ask which they want, and write the rule only with their yes",
}

// TestInstallerSaysWhenADeployWorkflowOnlyHandsOff: step 3, which reads the
// deploy workflows to propose a rule, says it.
func TestInstallerSaysWhenADeployWorkflowOnlyHandsOff(t *testing.T) {
	wantAll(t, "agent-installer.md step 3", asOneLine(section(t, installerFile, "Step 3.")), handOffSentences...)
}

// TestUpgraderSaysWhenADeployWorkflowOnlyHandsOff: item 6 of step 5, which
// reads the workflow behind each rule it proposes, says it too.
func TestUpgraderSaysWhenADeployWorkflowOnlyHandsOff(t *testing.T) {
	wantAll(t, "agent-upgrade.md step 5", upgraderSection(t, "Step 5."), handOffSentences...)
}
