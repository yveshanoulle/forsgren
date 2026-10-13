package main

import (
	"fmt"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
	"github.com/yveshanoulle/forsgren/internal/page"
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

// TestRenderShowsTheIssuesOfEachDay (forsgren#76, step 10; forsgren#128): with
// data/issues.csv next to --data, days.html shows the UTC day before the
// render time, 2 October. Issue 7 is created that day; issues 8 to 11, created
// earlier, are closed that day, one for each reason, completed, not planned,
// duplicate and none: 1 in each column, and 1 issue still open, the Open.
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
	if issues := readFile(t, filepath.Join(dir, "days.html")); !strings.Contains(issues, want) {
		t.Errorf("want the page to hold the row %q, got:\n%s", want, issues)
	}
}

// TestRenderShowsTheIssuesOfWeeksAndMonthsOnTheIssuesPage (forsgren#89, step
// 17; forsgren#123, step 10): rendered on Wednesday 14 October 2026,
// issues.html holds the day before (13 October), then the complete weeks of
// the month, 41 and 40 (40 begins in September), then the months, September
// and August, each with an issue created in it. days.html holds no week or
// month row.
func TestRenderShowsTheIssuesOfWeeksAndMonthsOnTheIssuesPage(t *testing.T) {
	dir := renderOn14October(t, "2026-10-13", "2026-10-06", "2026-09-29", "2026-09-10", "2026-08-20")
	wantRowLabels(t, filepath.Join(dir, "issues.html"), true,
		"Period", "2026-10-13", "Week 41", "Week 40", "September 2026", "August 2026")
	wantRowLabels(t, filepath.Join(dir, "days.html"), false,
		"Week 41", "Week 40", "September 2026", "August 2026")
}

// TestRenderShowsTheYearRowsOnTheIssuesPage (forsgren#125, step 9): rendered
// on Wednesday 14 October 2026, issues.html holds the months of 2026 as month
// rows (September, the month with an issue created in it) and every earlier
// year as one row, 2025 and 2024, and no month row of those years.
func TestRenderShowsTheYearRowsOnTheIssuesPage(t *testing.T) {
	issuesPage := filepath.Join(renderOn14October(t, "2026-09-10", "2025-11-20", "2024-03-05"), "issues.html")
	wantRowLabels(t, issuesPage, true, "September 2026", "2025", "2024")
	wantRowLabels(t, issuesPage, false, "November 2025", "March 2024")
}

// renderOn14October renders the site on Wednesday 14 October 2026 from a
// history with one issue created at 09:00 UTC on each of the days (2006-01-02),
// numbered from 1, and returns the site's folder.
func renderOn14October(t *testing.T, days ...string) string {
	t.Helper()
	old := now
	now = func() time.Time { return time.Date(2026, 10, 14, 12, 0, 0, 0, time.UTC) }
	t.Cleanup(func() { now = old })
	data := writeHistory(t, acmeHistory())
	var events []history.IssueEvent
	for i, day := range days {
		events = append(events, issueEventAt(int64(i+1), "created", "", day+"T09:00:00Z"))
	}
	if _, err := history.AppendIssueEvents(filepath.Join(filepath.Dir(data), "issues.csv"), events); err != nil {
		t.Fatal(err)
	}
	dir := filepath.Join(t.TempDir(), "site")
	if code, _, stderr := runCommand("render", "--out", dir, "--config", writeConfig(t, validConfig),
		"--data", data); code != 0 {
		t.Fatalf("want exit 0, got %d (stderr %q)", code, stderr)
	}
	return dir
}

// wantRowLabels fails for each label the page at path lacks as a cell when
// present is true, or holds as a cell when present is false.
func wantRowLabels(t *testing.T, path string, present bool, labels ...string) {
	t.Helper()
	page := readFile(t, path)
	for _, label := range labels {
		if strings.Contains(page, ">"+label+"<") != present {
			t.Errorf("want %q on %s: %v, got:\n%s", label, filepath.Base(path), present, page)
		}
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

// TestRenderCountsTheOpenBugsFromTheBugFlagsFile (forsgren#126): with
// data/issue_bugs.csv next to the history, the rows of the issues carry the
// OpenBugs of the issues that file says are bugs: issue 7 is a bug and issue 8
// is not, both created on 2 October, so the day has 2 open and 1 open bug.
func TestRenderCountsTheOpenBugsFromTheBugFlagsFile(t *testing.T) {
	data := writeHistory(t, acmeHistory())
	events := []history.IssueEvent{
		issueEventAt(7, "created", "", "2026-10-02T09:00:00Z"),
		issueEventAt(8, "created", "", "2026-10-02T10:00:00Z"),
	}
	if _, err := history.AppendIssueEvents(filepath.Join(filepath.Dir(data), "issues.csv"), events); err != nil {
		t.Fatal(err)
	}
	bugs := []history.IssueBug{{Repository: "acme/api", Issue: 7, Bug: true}, {Repository: "acme/api", Issue: 8}}
	if _, err := history.AppendIssueBugs(filepath.Join(filepath.Dir(data), "issue_bugs.csv"), bugs); err != nil {
		t.Fatal(err)
	}
	got, err := withHistory(page.Data{}, config.Config{}, data, time.Date(2026, 10, 3, 12, 0, 0, 0, time.UTC))
	if err != nil {
		t.Fatal(err)
	}
	if day := got.IssueDays[0]; day.Open != 2 || day.OpenBugs != 1 {
		t.Errorf("want 2 open and 1 open bug on 2 October, got %d open and %d open bugs", day.Open, day.OpenBugs)
	}
}

// TestRenderRefusesABadBugFlagsFile (forsgren#126): a malformed or
// unknown-version issue_bugs.csv fails render with its own message, naming it,
// and writes nothing. Proven by mutation.
func TestRenderRefusesABadBugFlagsFile(t *testing.T) {
	head := "# forsgren issue bugs v1\nrepository,issue,bug\n"
	wantBadFileRefused(t, "issue_bugs.csv", map[string]badFile{
		"unknown version": {"# forsgren issue bugs v2\n", "unknown history format version"},
		"malformed line":  {head + "acme/api,7\n", "line 3: malformed history"},
	})
}
