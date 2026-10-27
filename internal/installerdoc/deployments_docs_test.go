package installerdoc

import "testing"

// Several deployment rules for one repository (forsgren#498, step 4, decision
// #499 A): the documents tell both forms, the refusals and what changes, and
// the installer asks whether a repository deploys in more than one way.

// TestConfigurationDescribesTheDeploymentsKey: the manual has the map of rule
// to label or to {label, paths}, the example of forsgren.be, and the refusals.
func TestConfigurationDescribesTheDeploymentsKey(t *testing.T) {
	wantAll(t, "docs/configuration.md", readRepoFileAsOneLine(t, "docs/configuration.md"),
		"**`deployments`** is the other form of `deployment`",
		"a map of deployment rule to label",
		"Each entry is its own row, labelled and counted as a service is",
		"`release: Releases`",
		"`environment=github-pages: {label: forsgren.be, paths: [README.md, cmd/readmepage/, "+
			"internal/readmepage/, internal/page/styles.css]}`",
		"An entry in the short form has no `paths`, so its Time to deploy per commit and its Commits per "+
			"deployment say `Per repository`",
		"`deployment` and `deployments` on one repository",
		"`deployments` beside `label` or `services`",
		"a deployment rule listed twice",
		"`deployments: {}`",
		"The total row counts every deployment of the repository")
}

// TestDataFilesSayHowAStoredDeploymentFindsItsRule: no change of the history
// format, a deployment's rule is its kind and name.
func TestDataFilesSayHowAStoredDeploymentFindsItsRule(t *testing.T) {
	wantAll(t, "docs/data-files.md", readRepoFileAsOneLine(t, "docs/data-files.md"),
		"With `deployments:` a stored deployment belongs to the rule with its kind and name",
		"the history format does not change",
		"one stream for each rule")
}

// TestPagesAndViewsDescribeTheRuleRow: the TBD rows chapter and the table.
func TestPagesAndViewsDescribeTheRuleRow(t *testing.T) {
	wantAll(t, "docs/pages-and-views.md", readRepoFileAsOneLine(t, "docs/pages-and-views.md"),
		"A repository with `deployments:` has a service row for each rule",
		"over the deployments of its kind and name",
		"`sub_rows: false` hides them")
}

// TestReleasesTellWhatUpgradingTo126MeansForDeployments: the release notes name
// the new key.
func TestReleasesTellWhatUpgradingTo126MeansForDeployments(t *testing.T) {
	wantAll(t, "docs/updating-and-releases.md", readRepoFileAsOneLine(t, "docs/updating-and-releases.md"),
		"(forsgren#498, decision #499)",
		"a repository can list several deployment rules with `deployments:`",
		"`deployment:` stays valid and nothing changes for an installation that does not use `deployments:`")
}

// TestTheInstallationReadmeTellsAboutDeployments: the README an installation
// gets.
func TestTheInstallationReadmeTellsAboutDeployments(t *testing.T) {
	wantAll(t, "install/README.md", readRepoFileAsOneLine(t, "install/README.md"),
		"A repository that deploys in more than one way can list its rules with `deployments:`")
}

// TestInstallerAsksWhetherARepositoryDeploysInMoreThanOneWay: question 16,
// and the line written in step 9.
func TestInstallerAsksWhetherARepositoryDeploysInMoreThanOneWay(t *testing.T) {
	wantAll(t, "agent-installer.md step 2", asOneLine(section(t, installerFile, "Step 2.")),
		"**Several ways to deploy.**",
		"whether a repository deploys in more than one way",
		"such as releases and a website",
		"`deployments:`",
		"only with the person's yes")
	wantAll(t, "agent-installer.md step 9", asOneLine(section(t, installerFile, "Step 9.")),
		"Write `deployments:` (question 16) only when the person said yes",
		"never beside `deployment`, `label` or `services`")
}

// TestUpgraderStaysTheSameForDeployments: the upgrader (checked, forsgren#498)
// still names a repository's `deployment:` line and asks nothing new, since
// `deployments:` is optional.
func TestUpgraderStaysTheSameForDeployments(t *testing.T) {
	wantAll(t, "agent-upgrade.md", asOneLine(readRepoFile(t, "agent-upgrade.md")),
		"Look at its `deployment:` line in `forsgren.config.yml`")
}
