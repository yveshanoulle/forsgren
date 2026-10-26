package main

import (
	"path/filepath"
	"strings"
	"testing"
)

// The fixture site's TBD page (forsgren#422, step 5): the made-up fixture of
// Scripts/testdata/fixture_site rendered through the real pipeline.

const fixtureSite = "../../Scripts/testdata/fixture_site"

// fixtureTbd is the TBD page of the fixture site.
func fixtureTbd(t *testing.T) string {
	t.Helper()
	pinNow(t)
	dir := filepath.Join(t.TempDir(), "site")
	code, _, stderr := runCommand("render", "--out", dir, "--config", fixtureSite+"/forsgren.config.yml",
		"--data", fixtureSite+"/data/deployments.csv")
	if code != 0 {
		t.Fatalf("want exit 0, got %d (stderr %q)", code, stderr)
	}
	return readFile(t, filepath.Join(dir, "tbd.html"))
}

// rowOf is the row of the page whose header reads label under project, up to
// its end; empty when there is none.
func rowOf(page, project, label string) string {
	_, rest, found := strings.Cut(page, `<span class="visually-hidden">`+project+`: </span>`+label+"</th>")
	row, _, _ := strings.Cut(rest, "</tr>")
	if !found {
		return ""
	}
	return row
}

// TestTheFixtureSiteShowsAServiceSubRow: Acme Shop's services Web and Admin
// are rows under its total, each with its own deployment cells and one cell
// across each of the four runs of per-repository cells.
func TestTheFixtureSiteShowsAServiceSubRow(t *testing.T) {
	page := fixtureTbd(t)
	for _, service := range []string{"Admin", "Web"} {
		row := rowOf(page, "Acme Shop", service)
		if got := strings.Count(row, "Per repository: see the project row"); got != 4 {
			t.Errorf("%s: want 4 per-repository cells in the service row, got %d in %q", service, got, row)
		}
	}
}

// TestTheFixtureSiteShowsARepositoryLabelRow: Acme Tools' repository label CLI
// is a row of its own with all its measures, never a per-repository cell.
func TestTheFixtureSiteShowsARepositoryLabelRow(t *testing.T) {
	row := rowOf(fixtureTbd(t), "Acme Tools", "CLI")
	if row == "" || strings.Contains(row, "Per repository") {
		t.Errorf("want a label row with every measure of its own, got %q", row)
	}
}
