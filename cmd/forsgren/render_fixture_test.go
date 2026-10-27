package main

import (
	"path/filepath"
	"strings"
	"testing"
	"unicode/utf8"
)

// labelCell is the header of a label row as the page writes it (forsgren#511, #526):
// the project visually hidden, the dash and the label, a label of up to 15
// characters with non-breaking spaces.
func labelCell(project, label string) string {
	dash, space := "– ", " "
	if utf8.RuneCountInString(label) <= 15 {
		dash, space = "–\u2060\u00a0", "\u00a0"
	}
	return `<th scope="row"><span class="visually-hidden">` + project + `: </span>` +
		`<span aria-hidden="true">` + dash + `</span>` + strings.ReplaceAll(label, " ", space) + "</th>"
}

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
	_, rest, found := strings.Cut(page, labelCell(project, label))
	row, _, _ := strings.Cut(rest, "</tr>")
	if !found {
		return ""
	}
	return row
}

// TestTheFixtureSiteShowsAServiceSubRow: Acme Shop's services Web and Admin
// are rows under its total, each with its own deployment cells and one cell
// across each of the four runs of per-repository cells; Admin, which has no
// paths, says Per repository for its Time to deploy, Deployed commits and
// Commits per deployment too (forsgren#496), while Web, with paths, shows its own.
func TestTheFixtureSiteShowsAServiceSubRow(t *testing.T) {
	page := fixtureTbd(t)
	for service, want := range map[string]int{"Admin": 7, "Web": 4} {
		row := rowOf(page, "Acme Shop", service)
		if got := strings.Count(row, "Per repository"); got != want {
			t.Errorf("%s: want %d per-repository cells in the service row, got %d in %q", service, want, got, row)
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

// TestTheFixtureSiteShowsTheRowsOfSeveralDeploymentRules (forsgren#498):
// Acme Shop's acme/ios-app lists two rules, so App (no paths) and
// Beta (the folder beta/) are service rows under its total, as services are:
// App says Per repository for its Time to deploy and Commits per
// deployment too, Beta shows its own.
func TestTheFixtureSiteShowsTheRowsOfSeveralDeploymentRules(t *testing.T) {
	page := fixtureTbd(t)
	for rule, want := range map[string]int{"App": 7, "Beta": 4} {
		row := rowOf(page, "Acme Shop", rule)
		if row == "" {
			t.Fatalf("want a service row %q under Acme Shop", rule)
		}
		if got := strings.Count(row, "Per repository"); got != want {
			t.Errorf("%s: want %d per-repository cells, got %d in %q", rule, want, got, row)
		}
	}
}
