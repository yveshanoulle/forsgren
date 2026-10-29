package installerdoc

import "testing"

// TestDocsSayWhatDataPageDoes (forsgren#579, step 4): the configuration
// reference names the key among the page keys, its default true, what the
// page shows, and lists it on the settings page; the installation README and
// the release notes name the Data page.
func TestDocsSayWhatDataPageDoes(t *testing.T) {
	config := readRepoFileAsOneLine(t, "docs/configuration.md")
	wantAll(t, "docs/configuration.md", config,
		"`history_page`, `tbd_page` and `data_page` are optional",
		"`tbd_page` is `true` (forsgren#409", "and `data_page` is `true`.",
		"**`data_page`**: the Data page (`data.html`, forsgren#579)",
		"`unlisted` keeps it out of the menu; `false` does not write it.",
		"`tbd_page`, `week_page`, `week_commits`, `data_page`, `tbd_figures`",
		"twenty-three rows in four columns", "for each of the six page keys")
	wantAll(t, "install/README.md", readRepoFileAsOneLine(t, "install/README.md"),
		"The Data page is in the menu by default (`data_page: true`)")
	wantAll(t, "docs/updating-and-releases.md", readRepoFileAsOneLine(t, "docs/updating-and-releases.md"),
		"**Upgrading to 1.31.0, which adds the Data page** (forsgren#579)",
		"an installation without `data_page` in its config gets the Data page in its menu")
}

// TestInstallerNamesDataPageAsALaterSetting: step 12's proof lists data_page
// as left to its default, and the settings that can be changed name it.
func TestInstallerNamesDataPageAsALaterSetting(t *testing.T) {
	proof := asOneLine(section(t, installerFile, "Step 12."))
	wantAll(t, "agent-installer.md step 12", proof, "`data_page` shows `true (not set)`")
	wantAll(t, string(installerFile), readRepoFileAsOneLine(t, installerFile),
		"`week_page`, `week_commits`, `data_page`, `tbd_figures`, `tbd_time_to_main`")
}
