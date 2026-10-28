package installerdoc

import "testing"

// TestDocsSayWhatWeekCommitsDoes (forsgren#548, decision #549 A): the
// configuration reference names the key, its default false when left out, that
// true brings back the Commits columns while the commits are still computed,
// and the refusal; the pages reference, the installation README and the
// upgrade note say it too.
func TestDocsSayWhatWeekCommitsDoes(t *testing.T) {
	wantAll(t, "docs/configuration.md", readRepoFileAsOneLine(t, "docs/configuration.md"),
		"**`week_commits`** is optional (forsgren#548",
		"`false`, the default, leaves the Commits columns out of the Week page",
		"`true` shows them under Total and under each weekday",
		"the commits are still computed",
		"`invalid week_commits \"yes\": use true or false`")
	wantAll(t, "docs/pages-and-views.md", readRepoFileAsOneLine(t, "docs/pages-and-views.md"),
		"**`week_commits`** (forsgren#548, decision #549)",
		"each with Deployments, Failed and Fail rate under it",
		"and Commits before them with `week_commits: true`")
	wantAll(t, "install/README.md", readRepoFileAsOneLine(t, "install/README.md"),
		"Its Commits columns are off by default (`week_commits: false`); set `week_commits: true` to show them.")
	wantAll(t, "docs/updating-and-releases.md", readRepoFileAsOneLine(t, "docs/updating-and-releases.md"),
		"**Upgrading to 1.29.3, which leaves the Week page's Commits columns out by default** (forsgren#548",
		"the Commits columns are gone unless the config says `week_commits: true`")
}
