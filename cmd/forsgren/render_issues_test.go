package main

import (
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// issueEventAt is an event of issue 7 of acme/api at the UTC time at
// (2006-01-02T15:04:05Z); reason is that of a closed event.
func issueEventAt(event, reason, at string) history.IssueEvent {
	when, err := time.Parse(time.RFC3339, at)
	if err != nil {
		panic(err)
	}
	return history.IssueEvent{Repository: "acme/api", Issue: 7, Event: event, Reason: reason, At: when}
}

// TestRenderShowsTheIssuesOfEachDay (forsgren#76, step 10): with
// data/issues.csv next to --data, issues.html shows the UTC day before the
// render time, 2 October, with the issue created and the issue completed on
// it, 1 New and 1 Completed.
func TestRenderShowsTheIssuesOfEachDay(t *testing.T) {
	pinNow(t)
	data := writeHistory(t, acmeHistory())
	events := []history.IssueEvent{
		issueEventAt("created", "", "2026-10-02T09:00:00Z"),
		issueEventAt("closed", "completed", "2026-10-02T15:00:00Z"),
	}
	if _, err := history.AppendIssueEvents(filepath.Join(filepath.Dir(data), "issues.csv"), events); err != nil {
		t.Fatal(err)
	}
	dir := filepath.Join(t.TempDir(), "site")
	if code, _, stderr := runCommand("render", "--out", dir, "--config", writeConfig(t, validConfig),
		"--data", data); code != 0 {
		t.Fatalf("want exit 0, got %d (stderr %q)", code, stderr)
	}
	want := "<th scope=\"row\">2026-10-02</th>\n            <td>1</td>\n            <td>1</td>\n"
	if issues := readFile(t, filepath.Join(dir, "issues.html")); !strings.Contains(issues, want) {
		t.Errorf("want the page to hold the row %q, got:\n%s", want, issues)
	}
}
