package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// tbdSiteOf renders validConfig with tbd_page: true and the config line
// extra, over the data at path (none when empty), and returns tbd.html.
func tbdSiteOf(t *testing.T, extra, path string) string {
	t.Helper()
	args := []string{"--config", writeConfig(t, extra+tbdOn)}
	if path != "" {
		args = append(args, "--data", path)
	}
	return readSite(t, renderInto(t, args...), "tbd.html")
}

// shopCell is Acme Shop's Mainline Interval cell over acmeCommits in the
// 30 days: two gaps, and its three commits, stored without their lineage,
// timed by author date (forsgren#254, step 4).
const shopCell = "<td>2 d 22 h ± 4 d 3 h (2) · median 2 d 22 h · p90 - · 3 commits timed by author date</td>"

// TestRenderShowsTheMainlineIntervalOfEachProject (forsgren#253, step 5): with
// the commits beside --data, tbd.html has a row per project with its Mainline
// Interval over the DORA window, counted as lead time is: Acme Shop's three
// commits in the 30 days (authored 2026-09-25 12:00, 2026-10-01 09:13 and
// 09:35; the one deployed on 2026-08-20 and acme/gone's are out) have two gaps
// of 141 h 13 min and 22 min; Acme Tools has no commit, so "-".
func TestRenderShowsTheMainlineIntervalOfEachProject(t *testing.T) {
	pinNow(t)
	got := tbdSiteOf(t, validConfig, writeData(t, acmeHistory(), acmeCommits()))
	for _, want := range []string{
		"<th scope=\"row\">Acme Shop</th>\n            " + shopCell,
		"<th scope=\"row\">Acme Tools</th>\n            <td>-</td>",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("want %q in tbd.html, got:\n%s", want, got)
		}
	}
	if strings.Contains(got, "no Mainline Interval to show") || strings.Contains(got, shaPrefix) {
		t.Errorf("want the table and no SHA, got:\n%s", got)
	}
}

// TestRenderMainlineIntervalFollowsTheStoredLineage (forsgren#254, step 4):
// with the parents and committer dates in the commits file, tbd.html counts
// the first-parent commits at their committer dates: of deployment 1's two
// commits, the branch commit its merge brought in is left out, so Acme Shop
// has deployment 3's commit, committed 2026-09-26 11:00, and the merge,
// committed 2026-10-01 09:25: one gap of 4 d 22 h, none by author date.
func TestRenderMainlineIntervalFollowsTheStoredLineage(t *testing.T) {
	pinNow(t)
	base := shippedWith("Acme/API", 3, "2026-09-25T12:00:00Z", "2026-09-26T12:00:00Z")
	branch := shippedWith("acme/api", 1, "2026-09-30T10:00:00Z", "2026-10-01T09:30:00Z")
	merge := shippedWith("acme/api", 1, "2026-10-01T09:20:00Z", "2026-10-01T09:30:00Z")
	base.Parents, base.CommittedAt = []string{shaPrefix + strings.Repeat("0", 34)}, utcAt(t, "2026-09-26T11:00:00Z")
	branch.Parents, branch.CommittedAt = []string{base.SHA}, branch.AuthoredAt
	merge.Parents, merge.CommittedAt = []string{base.SHA, branch.SHA}, utcAt(t, "2026-10-01T09:25:00Z")
	got := tbdSiteOf(t, validConfig, writeData(t, acmeHistory(), []history.Commit{base, branch, merge}))
	if want := "<td>4 d 22 h ± - (1) · median - · p90 -</td>"; !strings.Contains(got, want) {
		t.Errorf("want %q in tbd.html, got:\n%s", want, got)
	}
}

// utcAt is the UTC time s, 2006-01-02T15:04:05Z.
func utcAt(t *testing.T, s string) time.Time {
	t.Helper()
	v, err := time.Parse(time.RFC3339, s)
	if err != nil {
		t.Fatal(err)
	}
	return v
}

// TestRenderShowsTheDevelopersOfEachProject (forsgren#273, step 3): with the
// authors in the commits file, tbd.html shows each project's Developers next
// to its Mainline Interval: of Acme Shop's three commits in the 30 days, one
// is by a made-up developer, one by a bot (left out) and one without a known
// author (named in the note); the developer of the commit deployed before the
// window is not counted. Acme Tools has no commit, so 0.
func TestRenderShowsTheDevelopersOfEachProject(t *testing.T) {
	pinNow(t)
	commits := acmeCommits()
	commits[0].Author, commits[1].Author = "acme-dev-one", "dependabot[bot]"
	commits[3].Author = "acme-dev-two"
	got := tbdSiteOf(t, validConfig, writeData(t, acmeHistory(), commits))
	for _, want := range []string{
		"<th scope=\"col\">Developers</th>",
		shopCell + "\n" +
			"            <td>1 · 1 commit without a known author is not counted</td>",
		"<th scope=\"row\">Acme Tools</th>\n            <td>-</td>\n            <td>0</td>",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("want %q in tbd.html, got:\n%s", want, got)
		}
	}
}

// TestRenderTbdPageUsesTheDoraWindow (forsgren#253, step 5; forsgren#271):
// dora_days reaches the Mainline Interval as it reaches lead time: over 90 days
// the commit deployed on 2026-08-20 (authored 2026-08-19 10:00) counts too, so
// three gaps of 890 h, 141 h 13 min and 22 min; the legend, not the page, names
// the window.
func TestRenderTbdPageUsesTheDoraWindow(t *testing.T) {
	pinNow(t)
	dir := renderInto(t, "--config", writeConfig(t, validConfig+"dora_days: 90\n"+tbdOn),
		"--data", writeData(t, acmeHistory(), acmeCommits()))
	const cell = "<td>14 d 7 h ± 19 d 22 h (3) · median 5 d 21 h · p90 - · 4 commits timed by author date</td>"
	if got := readSite(t, dir, "tbd.html"); !strings.Contains(got, cell) {
		t.Errorf("want Acme Shop's three gaps over 90 days, got:\n%s", got)
	}
	if got := readSite(t, dir, "legend.html"); !strings.Contains(got, "deployments of the last 90 days shipped") {
		t.Errorf("want the legend to name the 90 days, got:\n%s", got)
	}
}

// TestRenderTbdPageWithoutProjectsOrData (forsgren#253, step 5): no projects
// keep the no-projects line, with data or not; projects but no --data say that
// no commits were collected.
func TestRenderTbdPageWithoutProjectsOrData(t *testing.T) {
	pinNow(t)
	none := "version: 1\nprojects: []\n"
	cases := map[string]struct{ got, want string }{
		"no projects with data": {tbdSiteOf(t, none, writeHistory(t, acmeHistory())),
			"No projects are listed yet, so there is no Mainline Interval to show."},
		"no projects, no data": {tbdSiteOf(t, none, ""),
			"No projects are listed yet, so there is no Mainline Interval to show."},
		"projects, no data": {tbdSiteOf(t, validConfig, ""),
			"No commits have been collected yet, so there is no Mainline Interval to show."},
	}
	for name, c := range cases {
		if !strings.Contains(c.got, "<p>"+c.want+"</p>") || strings.Contains(c.got, "<table") {
			t.Errorf("%s: want the line %q and no table, got:\n%s", name, c.want, c.got)
		}
	}
}

// TestRenderWritesNoTbdPageWhenTheKeyIsFalse (forsgren#253, step 5): with
// tbd_page: false and the data the page needs there is no tbd.html and no
// menu entry for it; a file left by an earlier run is removed.
func TestRenderWritesNoTbdPageWhenTheKeyIsFalse(t *testing.T) {
	pinNow(t)
	data := writeData(t, acmeHistory(), acmeCommits())
	dir := filepath.Join(t.TempDir(), "site")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "tbd.html"), []byte("stale"), 0o600); err != nil {
		t.Fatal(err)
	}
	file := writeConfig(t, validConfig+"tbd_page: "+string(config.PageOff)+"\n")
	if code, _, stderr := runCommand("render", "--out", dir, "--config", file, "--data", data); code != 0 {
		t.Fatalf("want exit 0, got %d (stderr %q)", code, stderr)
	}
	if _, err := os.Stat(filepath.Join(dir, "tbd.html")); err == nil {
		t.Error("want the stale tbd.html removed and none written")
	}
	if strings.Contains(readSite(t, dir, "index.html"), "tbd.html") {
		t.Error("want no link to tbd.html in the menu")
	}
}
