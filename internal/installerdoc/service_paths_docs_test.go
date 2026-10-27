package installerdoc

import "testing"

// The paths of a service (forsgren#496, decision #497 A, step 5): the
// documents tell how to write them and what they change, and the installer
// and the upgrader ask for each service's folders and write the long form.

// TestConfigurationDescribesThePathsOfAService: the manual has both forms of a
// service, how to write a path, and the rules of decision #497.
func TestConfigurationDescribesThePathsOfAService(t *testing.T) {
	wantAll(t, "docs/configuration.md", readRepoFileAsOneLine(t, "docs/configuration.md"),
		"A service is a label alone, or a label with `paths`",
		"`deploy-api: {label: API, paths: [api/, shared/]}`",
		"A path ending in `/` is a folder and matches everything below it; "+
			"any other path is a file and matches that file exactly",
		"No glob, no absolute path and no `..`",
		"`shared/` counts for a service only where its `paths` list it",
		"Files in the root of the repository, such as `.github/`, `go.mod`, `Scripts/` and `docs/`, count for no service",
		"A commit that touches the paths of several services counts once for each of them",
		"A commit that touches none counts for no service",
		"There is no `shared_paths` key and no implicit fallback",
		"The total row and the label rows count every commit of the repository",
		"A service without `paths` says `Per repository` for its Time to deploy per commit and its Commits per deployment",
		"`Files still being read` (note 8)")
}

// TestDataFilesDescribeTheCommitFiles: the data format and how collect reads
// the files, last and in a budget.
func TestDataFilesDescribeTheCommitFiles(t *testing.T) {
	wantAll(t, "docs/data-files.md", readRepoFileAsOneLine(t, "docs/data-files.md"),
		"`data/commit_files.csv`",
		"`repository,sha,path`",
		"one `GET /repos/{owner}/{repo}/commits/{sha}` per commit",
		"A commit that was read and changes no file is one line with an empty path",
		"a rename has a line for the new name and one for the previous name",
		"`data/commit_files_filled.csv`",
		"The files are read last for a repository, after the fresh data",
		"only for a repository with a service or a deployment rule that has `paths`",
		"`commit-files-cut`")
}

// TestPagesAndViewsDescribeTheServiceRow: the service row's figures and note 8.
func TestPagesAndViewsDescribeTheServiceRow(t *testing.T) {
	wantAll(t, "docs/pages-and-views.md", readRepoFileAsOneLine(t, "docs/pages-and-views.md"),
		"A service with `paths` counts only the commits that touch them",
		"A service without `paths` says `Per repository`",
		"(8) Files still being read",
		"The total row and the label rows count every commit")
}

// TestReleasesTellWhatUpgradingTo126Changes: the release notes name the
// change for an installation with services.
func TestReleasesTellWhatUpgradingTo126Changes(t *testing.T) {
	wantAll(t, "docs/updating-and-releases.md", readRepoFileAsOneLine(t, "docs/updating-and-releases.md"),
		"Upgrading to 1.26.0",
		"an installation with services",
		"`Per repository` for the Time to deploy per commit and the Commits per deployment",
		"until you add `paths`",
		"`deploy-api: {label: API, paths: [api/, shared/]}`")
}

// TestTheInstallationReadmeTellsAboutPaths: the README an installation gets.
func TestTheInstallationReadmeTellsAboutPaths(t *testing.T) {
	wantAll(t, "install/README.md", readRepoFileAsOneLine(t, "install/README.md"),
		"A service can name its folders with `paths`",
		"`Per repository`")
}

// TestInstallerAsksForTheFoldersOfEachService: the installer asks, per
// repository with services, which folders each service builds from, and writes
// the long form.
func TestInstallerAsksForTheFoldersOfEachService(t *testing.T) {
	wantAll(t, "agent-installer.md step 2", asOneLine(section(t, installerFile, "Step 2.")),
		"**Services and their folders.**",
		"which folders each service is built from",
		"A folder ends in `/`",
		"`shared/` only where the person lists it",
		"only with the person's yes")
	wantAll(t, "agent-installer.md step 9", asOneLine(section(t, installerFile, "Step 9.")),
		"`deploy-api: {label: API, paths: [api/, shared/]}`",
		"the short form `deploy-api: API` only for a service the person gave no folders")
}

// TestUpgraderTellsAnInstallationWithServicesAboutPaths: upgrading to this
// release, the service rows show Per repository until paths are added; the
// upgrader says so, how to find the folders, and writes the lines with a yes.
func TestUpgraderTellsAnInstallationWithServicesAboutPaths(t *testing.T) {
	wantAll(t, "agent-upgrade.md step 5", upgraderSection(t, "Step 5."),
		"**Service folders**",
		"`services:` without `paths`",
		"`Per repository` for the deploy figures until it has `paths`",
		"the folders of the repository on GitHub",
		"the `paths:` filter of its deploy workflow",
		"`deploy-web: {label: Web, paths: [web/, shared/]}`",
		"only with the person's yes")
	wantAll(t, "agent-upgrade.md step 8", upgraderSection(t, "Step 8."),
		"`paths`", "service")
}
