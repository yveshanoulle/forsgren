package main

import (
	"path/filepath"
	"strings"
	"testing"
)

// fixtureWeekPage is week.html of the fixture rendered through the real
// pipeline.
func fixtureWeekPage(t *testing.T) string {
	t.Helper()
	pinNow(t)
	dir := filepath.Join(t.TempDir(), "site")
	code, _, stderr := runCommand("render", "--out", dir, "--config", fixtureSite+"/forsgren.config.yml",
		"--data", fixtureSite+"/data/deployments.csv")
	if code != 0 {
		t.Fatalf("want exit 0, got %d (stderr %q)", code, stderr)
	}
	return readFile(t, filepath.Join(dir, "week.html"))
}

// TestTheFixtureSiteWritesTheWeekPage (forsgren#531, step 2; forsgren#540):
// the fixture has week.html with its window, the weekday group headers, a
// total row per project and a service row without paths (Acme Shop's Web and
// Admin) with an en dash for its commits.
func TestTheFixtureSiteWritesTheWeekPage(t *testing.T) {
	page := fixtureWeekPage(t)
	for _, want := range []string{`<h1 id="week-heading">Week</h1>`, "every weekday of that window counted (UTC).",
		`<th scope="colgroup" colspan="2">Sunday</th>`, `<th scope="row">Acme Shop</th>`, "<td>–</td>"} {
		if !strings.Contains(page, want) {
			t.Errorf("want %q in the Week page of the fixture site", want)
		}
	}
}

// TestTheFixtureWeekPageHasNoWeekendShareAndFiguresForARepositoryLabel: the
// column is gone (decision #541), and the repository label CLI has figures of
// its own.
func TestTheFixtureWeekPageHasNoWeekendShareAndFiguresForARepositoryLabel(t *testing.T) {
	page := fixtureWeekPage(t)
	row := rowOf(page, "Acme Tools", "CLI")
	if strings.Contains(page, "Weekend share") || !strings.Contains(row, `class="num"`) {
		t.Errorf("want figure cells in the CLI row and no Weekend share, got %q", row)
	}
}
