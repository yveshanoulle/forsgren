package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// readSite is the file name of the site in dir.
func readSite(t *testing.T, dir, name string) string {
	t.Helper()
	return readFile(t, filepath.Join(dir, name))
}

// writeReach stores the reach beside the history at data, every repository of
// validConfig read back to at.
func writeReach(t *testing.T, data string, at time.Time) {
	t.Helper()
	reach := history.Reach{"acme/api": at, "acme/ios-app": at, "acme/cli": at}
	if err := history.SaveReach(filepath.Join(filepath.Dir(data), "reach.csv"), reach); err != nil {
		t.Fatal(err)
	}
}

// olderHistory is acmeHistory with a success of acme/api in March 2026, so the
// half-year before the last 6 months has a deployment too.
func olderHistory() []history.Record {
	return append(acmeHistory(), shipped(200, "acme/api", history.StateSuccess, "2026-03-01T12:00:00Z"))
}

// TestRenderShowsTheHistoryPagePeriods (forsgren#68): with the history and the
// reach beside it, history.html has a column per period that has data, the
// half-year that history_days (365) reaches and the last 6 months, oldest
// first; the periods before the reach of a repository are not shown.
func TestRenderShowsTheHistoryPagePeriods(t *testing.T) {
	pinNow(t)
	data := writeHistory(t, olderHistory())
	writeReach(t, data, time.Date(2025, time.October, 1, 0, 0, 0, 0, time.UTC))
	dir := renderInto(t, "--config", writeConfig(t, historyOn+validConfig), "--data", data)
	got := readSite(t, dir, "history.html")
	first, second := `<th scope="col">2026 H1</th>`, `<th scope="col">Last 6 months to 2026-10-03</th>`
	if !strings.Contains(got, first+"\n            "+second) {
		t.Errorf("want the columns 2026 H1 and Last 6 months in order, got:\n%s", got)
	}
	if !strings.Contains(got, "<td>1 · 2</td>") {
		t.Errorf("want Acme Shop's 2026 H1 deployment, 1 · 2, in the frequency group, got:\n%s", got)
	}
	unread := writeHistory(t, olderHistory())
	writeReach(t, unread, time.Date(2026, time.March, 1, 0, 0, 0, 0, time.UTC))
	late := readSite(t, renderInto(t, "--config", writeConfig(t, historyOn+validConfig), "--data", unread), "history.html")
	if strings.Contains(late, "2026 H1") || !strings.Contains(late, "Last 6 months") {
		t.Errorf("want only the last 6 months when the history is read back to March 2026, got:\n%s", late)
	}
}

// TestRenderSaysHowToGetHistory (forsgren#68): without a reach file nothing is
// read yet, and with history_days under 180 the page names the fix.
func TestRenderSaysHowToGetHistory(t *testing.T) {
	pinNow(t)
	data := writeHistory(t, olderHistory())
	config := writeConfig(t, historyOn+validConfig)
	nothing := readSite(t, renderInto(t, "--config", config, "--data", data), "history.html")
	if !strings.Contains(nothing, "No history to show yet") {
		t.Errorf("want the no-history line without a reach file, got:\n%s", nothing)
	}
	writeReach(t, data, time.Date(2025, time.October, 1, 0, 0, 0, 0, time.UTC))
	config = writeConfig(t, historyOn+"history_days: 90\n"+validConfig)
	short := readSite(t, renderInto(t, "--config", config, "--data", data), "history.html")
	if !strings.Contains(short, "history_days is 90, too short for the last 6 months: set history_days to at least 180") {
		t.Errorf("want the short history line, got:\n%s", short)
	}
}

// TestHistoryPageIsHiddenByDefault (forsgren#68, #199, #200): history.html is
// left out only when history_page is false; absent and a value that is not
// accepted (the default unlisted is in force) write it, and until the menu
// learns unlisted (#200 steps 5 to 8) they list it like true; without
// --config nothing is hidden.
func TestHistoryPageIsHiddenByDefault(t *testing.T) {
	cases := map[string]struct {
		keys string
		want bool
	}{
		"absent": {"", true}, "true": {"history_page: true\n", true},
		"false": {"history_page: false\n", false}, "not accepted": {"history_page: yes\n", true},
	}
	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			dir := renderInto(t, "--config", writeConfig(t, tc.keys+validConfig))
			wantHistoryPage(t, dir, tc.want)
		})
	}
	t.Run("no --config", func(t *testing.T) { wantHistoryPage(t, renderInto(t), true) })
}

// TestRenderRemovesAStaleHistoryPageWhenTheKeyIsFalse (forsgren#199, #200): an
// out dir that holds the history.html of an earlier run with history_page:
// true loses it when the config sets history_page: false.
func TestRenderRemovesAStaleHistoryPageWhenTheKeyIsFalse(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "site")
	for _, keys := range []string{"history_page: true\n", "history_page: false\n"} {
		args := []string{"render", "--out", dir, "--config", writeConfig(t, keys+validConfig)}
		if code, _, stderr := runCommand(args...); code != 0 {
			t.Fatalf("want exit 0, got %d (stderr %q)", code, stderr)
		}
		wantHistoryPage(t, dir, keys == "history_page: true\n")
	}
}

// wantHistoryPage fails unless history.html is written exactly when want, and
// the menu of index.html links it exactly then.
func wantHistoryPage(t *testing.T, dir string, want bool) {
	t.Helper()
	if _, err := os.Stat(filepath.Join(dir, "history.html")); (err == nil) != want {
		t.Errorf("want history.html written: %v, got %v", want, err)
	}
	if got := strings.Contains(readSite(t, dir, "index.html"), `href="history.html"`); got != want {
		t.Errorf("want the menu to link history.html: %v, got %v", want, got)
	}
}

// TestRenderRefusesABadReach (forsgren#68): a reach file of an unknown format
// fails render with the file's own message, and writes no page.
func TestRenderRefusesABadReach(t *testing.T) {
	data := writeHistory(t, acmeHistory())
	reach := filepath.Join(filepath.Dir(data), "reach.csv")
	if err := os.WriteFile(reach, []byte("# forsgren reach v9\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	wantRefused(t, data, reach, "unknown")
}

// TestRenderMatchesTheReachWhateverTheCase (forsgren#196): a repository is the
// same whichever way its name is written, in the config or in reach.csv, as
// collect compares them; a reach row written Acme/API reads the config's
// acme/api, and the History page shows the period it was read back to.
func TestRenderMatchesTheReachWhateverTheCase(t *testing.T) {
	pinNow(t)
	data := writeHistory(t, olderHistory())
	at := time.Date(2025, time.October, 1, 0, 0, 0, 0, time.UTC)
	reach := history.Reach{"Acme/API": at, "ACME/ios-app": at, "acme/CLI": at}
	if err := history.SaveReach(filepath.Join(filepath.Dir(data), "reach.csv"), reach); err != nil {
		t.Fatal(err)
	}
	got := readSite(t, renderInto(t, "--config", writeConfig(t, historyOn+validConfig), "--data", data), "history.html")
	if !strings.Contains(got, `<th scope="col">2026 H1</th>`) {
		t.Errorf("want the half-year the repositories were read back to, got:\n%s", got)
	}
}
