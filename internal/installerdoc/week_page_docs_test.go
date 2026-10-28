package installerdoc

import "testing"

// TestDocsSayWhatWeekPageDoes (forsgren#531, step 3, decision #533 A): the
// configuration reference names the key, its default true when left out, that
// false takes the page out of the menu while the page is still written and
// reachable by its address, and lists it on the settings page; the pages
// reference and the installation README name the Week page.
func TestDocsSayWhatWeekPageDoes(t *testing.T) {
	config := readRepoFileAsOneLine(t, "docs/configuration.md")
	wantAll(t, "docs/configuration.md", config, "**`week_page`** is optional (forsgren#531",
		"`true`, the default, lists the Week page in the menu",
		"`false` takes it out of the menu",
		"still written and reachable by its address, `week.html`",
		"`tbd_page`, `week_page`, `week_commits`, `tbd_figures`", "twenty-two rows in four columns",
		"and for `week_page` and `week_commits`", "`true`, `true`, `false`, `median`")
	wantAll(t, "install/README.md", readRepoFileAsOneLine(t, "install/README.md"),
		"The Week page is in the menu by default (`week_page: true`)")
	wantAll(t, "docs/updating-and-releases.md", readRepoFileAsOneLine(t, "docs/updating-and-releases.md"),
		"an installation without `week_page` in its config gets the Week page in its menu")
}

// TestInstallerNamesWeekPageAsALaterSetting: step 12's proof lists week_page
// as left to its default.
func TestInstallerNamesWeekPageAsALaterSetting(t *testing.T) {
	proof := asOneLine(section(t, installerFile, "Step 12."))
	wantAll(t, "agent-installer.md step 12", proof, "`week_page` shows `true (not set)`")
}
