package main

import (
	"path/filepath"
	"strings"
	"testing"
)

// TestTheFixtureSiteWritesTheWeekPage (forsgren#531, step 2): the fixture
// rendered through the real pipeline has week.html with its window, the
// weekday headers, a total row per project, a service row Per repository
// (Acme Shop's Web and Admin have no paths) with an en dash for its commits and its deployments, and
// the repository label CLI with figures of its own.
func TestTheFixtureSiteWritesTheWeekPage(t *testing.T) {
	pinNow(t)
	dir := filepath.Join(t.TempDir(), "site")
	code, _, stderr := runCommand("render", "--out", dir, "--config", fixtureSite+"/forsgren.config.yml",
		"--data", fixtureSite+"/data/deployments.csv")
	if code != 0 {
		t.Fatalf("want exit 0, got %d (stderr %q)", code, stderr)
	}
	page := readFile(t, filepath.Join(dir, "week.html"))
	for _, want := range []string{`<h1 id="week-heading">Week</h1>`, "every weekday of that window counted (UTC).",
		`<th scope="col" class="num">Sun</th>`, `<th scope="row">Acme Shop</th>`, "<td>– · "} {
		if !strings.Contains(page, want) {
			t.Errorf("want %q in the Week page of the fixture site", want)
		}
	}
	row := rowOf(page, "Acme Tools", "CLI")
	if strings.Contains(row, "Per repository") || !strings.Contains(row, `class="num"`) {
		t.Errorf("want figure cells in the CLI row, got %q", row)
	}
}
