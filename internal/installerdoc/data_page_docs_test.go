package installerdoc

import (
	"strings"
	"testing"
)

// TestDocsSayWhatDataPageDoes (forsgren#579, step 4): the configuration
// reference names the key among the page keys, its default true, what the
// page shows, and lists it on the settings page; the installation README and
// the release notes name the Data page. Since forsgren#582 the page is linked
// in the footer, not the menu.
func TestDocsSayWhatDataPageDoes(t *testing.T) {
	config := readRepoFileAsOneLine(t, "docs/configuration.md")
	wantAll(t, "docs/configuration.md", config,
		"`history_page`, `tbd_page` and `data_page` are optional",
		"`tbd_page` is `true` (forsgren#409", "and `data_page` is `true`.",
		"**`data_page`**: the Data page (`data.html`, forsgren#579)",
		"`true` links it in the footer, next to Settings, Legend and Dictionary; "+
			"`unlisted` writes it without the link; `false` does not write it.",
		"`tbd_page`, `week_page`, `week_commits`, `data_page`, `tbd_figures`",
		"twenty-three rows in four columns", "for each of the six page keys")
	wantAll(t, "install/README.md", readRepoFileAsOneLine(t, "install/README.md"),
		"The Data page is linked in the footer by default (`data_page: true`)")
	wantAll(t, "docs/updating-and-releases.md", readRepoFileAsOneLine(t, "docs/updating-and-releases.md"),
		"**Upgrading to 1.31.0, which adds the Data page** (forsgren#579)",
		"an installation without `data_page` in its config gets a Data link in its footer")
	for file, text := range map[string]string{"docs/configuration.md": config,
		"install/README.md":             readRepoFileAsOneLine(t, "install/README.md"),
		"docs/updating-and-releases.md": readRepoFileAsOneLine(t, "docs/updating-and-releases.md"),
		"docs/pages-and-views.md":       readRepoFileAsOneLine(t, "docs/pages-and-views.md")} {
		for _, stale := range []string{"Data page in its menu", "lists it in the menu, after Week", "· Week · Data"} {
			if strings.Contains(text, stale) {
				t.Errorf("%s still says %q: the Data page is in the footer since forsgren#582", file, stale)
			}
		}
	}
}

// TestInstallerNamesDataPageAsALaterSetting: step 12's proof lists data_page
// as left to its default, and the settings that can be changed name it.
func TestInstallerNamesDataPageAsALaterSetting(t *testing.T) {
	proof := asOneLine(section(t, installerFile, "Step 12."))
	wantAll(t, "agent-installer.md step 12", proof, "`data_page` shows `true (not set)`",
		"(the Data page, `data.html`, is generated and linked in the footer)")
	wantAll(t, string(installerFile), readRepoFileAsOneLine(t, installerFile),
		"`week_page`, `week_commits`, `data_page`, `tbd_figures`, `tbd_time_to_main`")
}
