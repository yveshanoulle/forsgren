package main

import (
	"fmt"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// issueEventAt is an event of issue number of acme/api at the UTC time at
// (2006-01-02T15:04:05Z); reason is that of a closed event.
func issueEventAt(number int64, event, reason, at string) history.IssueEvent {
	when, err := time.Parse(time.RFC3339, at)
	if err != nil {
		panic(err)
	}
	return history.IssueEvent{Repository: "acme/api", Issue: number, Event: event, Reason: reason, At: when}
}

// TestRenderShowsTheIssuesOfEachDay (forsgren#76, step 10): with
// data/issues.csv next to --data, issues.html shows the UTC day before the
// render time, 2 October. Issue 7 is created that day; issues 8 to 11, created
// earlier, are closed that day, one for each reason, completed, not planned,
// duplicate and none: 1 in each column, and 1 issue still open, the Total.
func TestRenderShowsTheIssuesOfEachDay(t *testing.T) {
	pinNow(t)
	data := writeHistory(t, acmeHistory())
	events := []history.IssueEvent{issueEventAt(7, "created", "", "2026-10-02T09:00:00Z")}
	for i, reason := range []string{"completed", "not_planned", "duplicate", ""} {
		events = append(events, issueEventAt(int64(8+i), "created", "", "2026-09-20T08:00:00Z"),
			issueEventAt(int64(8+i), "closed", reason, fmt.Sprintf("2026-10-02T%d:00:00Z", 15+i)))
	}
	if _, err := history.AppendIssueEvents(filepath.Join(filepath.Dir(data), "issues.csv"), events); err != nil {
		t.Fatal(err)
	}
	dir := filepath.Join(t.TempDir(), "site")
	if code, _, stderr := runCommand("render", "--out", dir, "--config", writeConfig(t, validConfig),
		"--data", data); code != 0 {
		t.Fatalf("want exit 0, got %d (stderr %q)", code, stderr)
	}
	want := "<th scope=\"row\">2026-10-02</th>\n" + strings.Repeat("            <td>1</td>\n", 6)
	if issues := readFile(t, filepath.Join(dir, "issues.html")); !strings.Contains(issues, want) {
		t.Errorf("want the page to hold the row %q, got:\n%s", want, issues)
	}
}

// TestRenderRefusesABadIssuesFile: a malformed or unknown-version issues
// file fails render with its own message, naming it, and writes nothing.
func TestRenderRefusesABadIssuesFile(t *testing.T) {
	head := "# forsgren issues v1\nrepository,issue,event,reason,at\n"
	wantBadFileRefused(t, "issues.csv", map[string]badFile{
		"unknown version": {"# forsgren issues v2\n", "unknown history format version"},
		"malformed line":  {head + "acme/api,7\n", "line 3: malformed history"},
	})
}
