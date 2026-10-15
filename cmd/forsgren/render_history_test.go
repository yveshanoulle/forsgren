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
	if strings.Contains(late, `<th scope="col">2026 H1</th>`) || !strings.Contains(late, "Last 6 months") {
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

// TestRenderTellsWhyTheHistoryPageHasOnePeriod (forsgren#198): with only the
// last 6 months holding data, history.html says when the first deployment of
// the listed repositories was and when the first half-year appears.
func TestRenderTellsWhyTheHistoryPageHasOnePeriod(t *testing.T) {
	pinNow(t)
	data := writeHistory(t, acmeHistory())
	writeReach(t, data, time.Date(2025, time.October, 1, 0, 0, 0, 0, time.UTC))
	got := readSite(t, renderInto(t, "--config", writeConfig(t, historyOn+validConfig), "--data", data), "history.html")
	const notice = "Only the last 6 months have data so far: the first deployment is 2026-08-20. " +
		"The first half-year, 2026 H2, appears on 2027-01-01."
	if !strings.Contains(got, notice) {
		t.Errorf("want the notice %q, got:\n%s", notice, got)
	}
}
