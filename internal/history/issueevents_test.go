package history

import (
	"os"
	"path/filepath"
	"slices"
	"testing"
	"time"
)

// TestAppendIssueEventsStoresThemInTimeOrderAndLoadReadsThemBack (forsgren#76,
// step 2): a new file gets the version line, the column line and one line per
// event, oldest first whatever the order given; LoadIssueEvents reads the same
// events back.
func TestAppendIssueEventsStoresThemInTimeOrderAndLoadReadsThemBack(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data", "issues.csv")
	created := IssueEvent{Repository: "acme/app", Issue: 7, Event: "created", At: day}
	closed := IssueEvent{
		Repository: "acme/app", Issue: 7, Event: "closed", Reason: "not_planned", At: day.Add(3 * time.Hour),
	}
	reopened := IssueEvent{Repository: "acme/app", Issue: 7, Event: "reopened", At: day.Add(26 * time.Hour)}
	n, err := AppendIssueEvents(path, []IssueEvent{reopened, created, closed})
	if err != nil || n != 3 {
		t.Fatalf("want 3 events stored, got %d, %v", n, err)
	}
	want := "# forsgren issues v1\n" +
		"repository,issue,event,reason,at\n" +
		"acme/app,7,created,,2026-09-01T10:00:00Z\n" +
		"acme/app,7,closed,not_planned,2026-09-01T13:00:00Z\n" +
		"acme/app,7,reopened,,2026-09-02T12:00:00Z\n"
	if got, _ := os.ReadFile(path); string(got) != want {
		t.Errorf("want the file\n%s\ngot\n%s", want, got)
	}
	got, err := LoadIssueEvents(path)
	if err != nil || !slices.Equal(got, []IssueEvent{created, closed, reopened}) {
		t.Errorf("want the three events in time order, got %v, %v", got, err)
	}
}
