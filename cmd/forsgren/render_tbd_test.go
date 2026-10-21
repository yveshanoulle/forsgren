package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/config"
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
		"<th scope=\"row\">Acme Shop</th>\n            <td>2 d 22 h ± 4 d 3 h (2)</td>",
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

// TestRenderTbdPageUsesTheDoraWindow (forsgren#253, step 5): dora_days reaches
// the Mainline Interval as it reaches lead time: over 90 days the commit
// deployed on 2026-08-20 (authored 2026-08-19 10:00) counts too, so three gaps
// of 890 h, 141 h 13 min and 22 min, and the page names the window.
func TestRenderTbdPageUsesTheDoraWindow(t *testing.T) {
	pinNow(t)
	got := tbdSiteOf(t, validConfig+"dora_days: 90\n", writeData(t, acmeHistory(), acmeCommits()))
	for _, want := range []string{"<td>14 d 7 h ± 19 d 22 h (3)</td>", "deployments of the last 90 days"} {
		if !strings.Contains(got, want) {
			t.Errorf("want %q (three gaps over 90 days, the window named), got:\n%s", want, got)
		}
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
