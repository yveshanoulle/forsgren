package installerdoc

import "testing"

// iosReleasesPage is the docs page on recording an iOS app's App Store
// releases as production deployments (forsgren#665).
const iosReleasesPage repoFile = "docs/ios-releases.md"

// TestIOSReleasesPageNamesTheRecipe (forsgren#665 step 1): the page tags
// every TestFlight upload, keeps TestFlight out of production, reads the live
// build from the App Store Connect API and maps it to the commit through the
// exact tag, keeps the marketing version consistent and bumps it after a
// release, says what forsgren then shows and the common pitfalls, and links
// Apple's and GitHub's API documentation.
func TestIOSReleasesPageNamesTheRecipe(t *testing.T) {
	wantAll(t, string(iosReleasesPage), readRepoFileAsOneLine(t, iosReleasesPage),
		"# iOS releases",
		"## Tag every TestFlight upload",
		"`v<marketing version>-<build>`",
		"## Record TestFlight uploads outside production",
		"`testflight`",
		"## The App Store release check",
		"`READY_FOR_SALE`",
		"ES256",
		"never the highest tag for the version",
		"idempotent",
		"fails closed",
		"## Keep the marketing version consistent",
		"`MARKETING_VERSION`",
		"next minor",
		"## What forsgren then shows",
		"## Common pitfalls",
		"https://developer.apple.com/documentation/appstoreconnectapi/",
		"https://docs.github.com/en/rest/deployments/deployments",
		"(configuration.md#giving-a-repository-the-deployments-forsgren-counts)")
}

// TestIOSReleasesPageDocumentsTheVersionBump (forsgren#679): the page's
// version-bump section says what starts the bump, where the live and the
// code's versions are read, how the next version is chosen and how the change
// reaches the default branch, with a minimal workflow example, the token's
// one permission and why it is not the job's token, the secret handling, the
// failure behaviour, and links to Apple's and GitHub's documentation.
func TestIOSReleasesPageDocumentsTheVersionBump(t *testing.T) {
	bump := asOneLine(section(t, iosReleasesPage, "Bump the marketing version after a release"))
	wantAll(t, string(iosReleasesPage), bump,
		"### What starts the bump",
		"`needs:`",
		"`workflow_dispatch`",
		"### Where the versions are read",
		"`versionString`",
		"### How the next version is chosen",
		"`none`", "`minor`", "`major`",
		"### How the change is persisted",
		"no force",
		"### Token, secret and permissions",
		"Contents: Read and write",
		"`persist-credentials: false`",
		"`contents: read`",
		"`concurrency`",
		"`VERSION_BUMP_TOKEN`",
		"### Failure behaviour",
		"### A minimal workflow",
		"```yaml",
		"path/to/project.pbxproj")
	wantAll(t, string(iosReleasesPage), readRepoFileAsOneLine(t, iosReleasesPage),
		"(#bump-the-marketing-version-after-a-release)",
		"https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/"+
			"trigger-a-workflow#triggering-a-workflow-from-a-workflow",
		"https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/"+
			"managing-your-personal-access-tokens#creating-a-fine-grained-personal-access-token",
		"https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets")
}

// TestIOSReleasesPageIsLinkedFromTheDocsLists (forsgren#665 step 1):
// README.md's Documentation list, docs/getting-started.md's reference list
// and the configuration page's deployment section link the page.
func TestIOSReleasesPageIsLinkedFromTheDocsLists(t *testing.T) {
	wantAll(t, "README.md", section(t, "README.md", "Documentation"),
		"- [iOS releases](docs/ios-releases.md)")
	wantAll(t, "docs/configuration.md",
		asOneLine(section(t, "docs/configuration.md", "Configuration")),
		"[iOS releases](ios-releases.md)")
	wantAll(t, "docs/getting-started.md", readRepoFileAsOneLine(t, "docs/getting-started.md"),
		"- [iOS releases](ios-releases.md)")
}
