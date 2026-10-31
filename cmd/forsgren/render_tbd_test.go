package main

import (
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// allSpan is the columns of a spread group with tbd_figures: all: the mean,
// the median, the p90 and the standard deviation (forsgren#588, step 2).
const allSpan = 4

// tbdSiteOf renders validConfig with tbd_page: true, tbd_figures: all (the
// tests below read the mean, the median, the p90 and the standard deviation
// of each measure; the
// median only is in render_tbd_figures_test.go, forsgren#423) and the config
// line extra, over the data at path (none when empty), and returns tbd.html.
func tbdSiteOf(t *testing.T, extra, path string) string {
	t.Helper()
	args := []string{"--config", writeConfig(t, extra+tbdOn+figuresAll)}
	if path != "" {
		args = append(args, "--data", path)
	}
	return readSite(t, renderInto(t, args...), "tbd.html")
}

// tdRow is the cells, each a td on a line of its own, as the template writes
// the cells of a row.
func tdRow(cells ...string) string {
	return "<td class=\"num\">" + strings.Join(cells, "</td>\n            <td class=\"num\">") + "</td>"
}

// noPushCells is a project's four Mainline Interval cells without a pushes
// file: the push state across them, as the Mainline Lead Time's (forsgren#588:
// the interval is read from the pushes, never from the deployed commits).
var (
	noPushCells = pushesNotCollected(allSpan)
	// shopTimes and noTimes are their time to deploy cells (forsgren#418).
	shopTimes = tdRow("8 h 5", "17 m", "-", "13 h 46")
	noTimes   = tdRow("-", "-", "-", "-")
	shopRow   = projectCells{noPushCells, shopTimes}
	noRow     = projectCells{noPushCells, noTimes}
)

// pushedAt is a push of repository at the UTC time pushed, its after SHA made
// from it, that brought the first-parent commits authored at the UTC times
// authored; branch ones are commits its merge brought in, off the
// first-parent chain.
type pushedAt struct {
	repository, pushed string
	authored, branch   []string
}

// stored is p as the pushes and push commits files hold it.
func (p pushedAt) stored(t *testing.T) (history.Push, []history.PushCommit) {
	t.Helper()
	at := utcAt(t, p.pushed)
	push := history.Push{Repository: p.repository, PushedAt: at, Before: pushShaBefore,
		After: fmt.Sprintf("%040x", at.Unix()), Kind: history.PushKindPush, Bot: history.ByHuman,
		Commits: int64(len(p.authored))}
	var commits []history.PushCommit
	for i, a := range append(slices.Clone(p.authored), p.branch...) {
		commits = append(commits, history.PushCommit{Repository: p.repository, After: push.After,
			SHA: fmt.Sprintf("%040x", utcAt(t, a).Unix()), Author: "acme-dev", AuthoredAt: utcAt(t, a),
			FirstParent: i < len(p.authored), Parents: 1})
	}
	return push, commits
}

// writePushedAt stores the pushes beside the history at data.
func writePushedAt(t *testing.T, data string, pushes ...pushedAt) {
	t.Helper()
	var all []history.Push
	var commits []history.PushCommit
	for _, p := range pushes {
		push, brought := p.stored(t)
		all, commits = append(all, push), append(commits, brought...)
	}
	storePushes(t, data, all, commits)
}

// acmePushes are the pushes of acme/api the interval tests read: one on 1
// October with the commits authored 25 September 12:00 and 1 October 09:13
// and a branch commit of 30 September, one on 2 October with the commits
// authored 1 October 09:35 and 2 October 09:00 (not deployed by
// acmeCommits), and one on 20 August, outside 30 days, with the commit
// authored 19 August 10:00.
func acmePushes() []pushedAt {
	return []pushedAt{
		{"acme/api", "2026-10-01T10:00:00Z", []string{"2026-09-25T12:00:00Z", "2026-10-01T09:13:00Z"},
			[]string{"2026-09-30T10:00:00Z"}},
		{"Acme/API", "2026-10-02T10:00:00Z", []string{"2026-10-01T09:35:00Z", "2026-10-02T09:00:00Z"}, nil},
		{"acme/api", "2026-08-20T10:00:00Z", []string{"2026-08-19T10:00:00Z"}, nil},
	}
}

// TestRenderShowsTheMainlineIntervalOfEachProject (forsgren#253, step 5; read
// from the pushes since forsgren#588): tbd.html has a row per project with its
// Mainline Interval over the DORA window: Acme Shop's four first-parent
// commits pushed in the 30 days, at their author dates (25 September 12:00,
// 1 October 09:13 and 09:35, 2 October 09:00; the branch commit and the push
// of 20 August are out, the commit pushed and not deployed counts), have gaps
// of 141 h 13 min, 22 min and 23 h 25 min: a mean of 55 h, a median of
// 23 h 25, no p90, and a sample standard deviation of the root of 20548119
// min², 3 d 3 h (forsgren#588, step 2); Acme Tools has no push, so "-" with
// no state.
func TestRenderShowsTheMainlineIntervalOfEachProject(t *testing.T) {
	pinNow(t)
	data := writeData(t, acmeHistory(), acmeCommits())
	writePushedAt(t, data, acmePushes()...)
	got := tbdSiteOf(t, validConfig, data)
	wantIn(t, got, "<th scope=\"row\">Acme Shop</th>\n            "+tdRow("2 d 7 h", "23 h 25", "-", "3 d 3 h"),
		"<th scope=\"row\">Acme Tools</th>\n            "+tdRow("-", "-", "-", "-"))
	if strings.Contains(got, "no Mainline Interval to show") || strings.Contains(got, shaPrefix) {
		t.Errorf("want the table and no SHA, got:\n%s", got)
	}
}

// TestRenderMainlineIntervalShowsThePushState (forsgren#588): with deployed
// commits and no pushes file, the interval of each project is the push state,
// not a figure from the deployed commits; a refused push read is not
// readable.
func TestRenderMainlineIntervalShowsThePushState(t *testing.T) {
	pinNow(t)
	data := writeData(t, acmeHistory(), acmeCommits())
	wantIn(t, tbdSiteOf(t, validConfig, data), "<th scope=\"row\">Acme Shop</th>\n            "+noPushCells,
		"<th scope=\"row\">Acme Tools</th>\n            "+noPushCells)
	writeMark(t, data, "pushes_denied.csv", pushesDeniedH2+"acme/api,2026-10-02T10:00:00Z,GITHUB_TOKEN\n")
	wantIn(t, tbdSiteOf(t, validConfig, data),
		"<th scope=\"row\">Acme Shop</th>\n            <td colspan=\"4\">Push activity not readable</td>")
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
// author (counted by the shares of the commits since forsgren#397, step 5);
// the developer of the commit deployed before the window is not counted.
// Acme Tools has no commit, so a dash. The PR Lead Time comes before
// the interval (forsgren#256, step 2), without a pull request the dash
// (forsgren#345, step 2).
func TestRenderShowsTheDevelopersOfEachProject(t *testing.T) {
	pinNow(t)
	commits := acmeCommits()
	commits[0].Author, commits[1].Author = "acme-dev-one", "dependabot[bot]"
	commits[3].Author = "acme-dev-two"
	data := writeData(t, acmeHistory(), commits)
	writePulls(t, data, nil)
	got := tbdSiteOf(t, validConfig, data)
	for _, want := range []string{
		"<th scope=\"colgroup\" colspan=\"1\">Developers</th>",
		developersRow("1"),
		developersRow("-"),
	} {
		if !strings.Contains(got, want) {
			t.Errorf("want %q in tbd.html, got:\n%s", want, got)
		}
	}
}

// TestRenderCountsTheLoginsOfASameDeveloperGroupOnce (forsgren#361, step 2):
// two made-up logins listed in one same_developer group are one developer in
// the Developers cell, whatever their case; without the key they are two.
func TestRenderCountsTheLoginsOfASameDeveloperGroupOnce(t *testing.T) {
	pinNow(t)
	commits := acmeCommits()
	commits[0].Author, commits[1].Author, commits[2].Author = "acme-dev-one", "dependabot[bot]", "Acme-Dev-Two"
	data := writeData(t, acmeHistory(), commits)
	writePulls(t, data, nil)
	grouped := tbdSiteOf(t, validConfig+"same_developer: [[acme-dev-one, acme-dev-two]]\n", data)
	if want := developersRow("1"); !strings.Contains(grouped, want) {
		t.Errorf("want one developer for the group in tbd.html, got:\n%s", grouped)
	}
	alone := tbdSiteOf(t, validConfig, data)
	if want := developersRow("2"); !strings.Contains(alone, want) {
		t.Errorf("want two developers without the key in tbd.html, got:\n%s", alone)
	}
}

// TestRenderTbdPageUsesTheDoraWindow (forsgren#253, step 5; forsgren#271):
// dora_days reaches the Mainline Interval as it reaches lead time: over 90 days
// the commit pushed on 2026-08-20 (authored 2026-08-19 10:00) counts too
// (forsgren#588: read from the pushes), so four gaps of 890 h, 141 h 13 min,
// 22 min and 23 h 25 min: a mean of 263 h 45 min, a median of 82 h 19 min; the
// legend, not the page, names the window.
func TestRenderTbdPageUsesTheDoraWindow(t *testing.T) {
	pinNow(t)
	data := writeData(t, acmeHistory(), acmeCommits())
	writePushedAt(t, data, acmePushes()...)
	dir := renderInto(t, "--config", writeConfig(t, validConfig+"dora_days: 90\n"+tbdOn+figuresAll), "--data", data)
	cell := tdRow("10 d 23 h", "3 d 10 h", "-")
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
