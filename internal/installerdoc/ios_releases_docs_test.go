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
