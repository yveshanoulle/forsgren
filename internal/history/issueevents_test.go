package history

import (
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
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
	if got, _ := os.ReadFile(filepath.Clean(path)); string(got) != want {
		t.Errorf("want the file\n%s\ngot\n%s", want, got)
	}
	got, err := LoadIssueEvents(path)
	if err != nil || !slices.Equal(got, []IssueEvent{created, closed, reopened}) {
		t.Errorf("want the three events in time order, got %v, %v", got, err)
	}
}

// issuesHead is the first two lines of an issues file; issueLine its good
// line, a closed event.
const (
	issuesHead = "# forsgren issues v1\nrepository,issue,event,reason,at\n"
	issueLine  = "acme/app,7,closed,completed,2026-09-01T10:00:00Z\n"
)

// TestAMalformedIssuesFileIsRefusedWithItsLineNumberAndReason: both calls
// name the line and say why (the reason is the line's own, not another
// rule's), and AppendIssueEvents leaves the file untouched.
func TestAMalformedIssuesFileIsRefusedWithItsLineNumberAndReason(t *testing.T) {
	edit := func(old, replacement string) string {
		return issuesHead + strings.Replace(issueLine, old, replacement, 1)
	}
	for name, c := range map[string]struct {
		content string
		line    int
		reason  string
	}{
		"bad issue number": {edit(",7,", ",7x,"), 3, `issue "7x" is not a whole number`},
		"bad time":         {edit("T10:00:00Z", "T10:00:00+02:00"), 3, `at "2026-09-01T10:00:00+02:00" is not RFC`},
		"unknown event":    {edit("closed", "deleted"), 3, `event "deleted" is not created, closed or reopened`},
		"reason on create": {
			edit("closed,completed", "created,completed"), 3, `reason "completed" does not fit a created event`,
		},
		"unknown reason": {edit("completed", "wontfix"), 3, `reason "wontfix" does not fit a closed event`},
	} {
		t.Run(name, func(t *testing.T) {
			path := writeFile(t, c.content)
			_, loadErr := LoadIssueEvents(path)
			_, appendErr := AppendIssueEvents(path, []IssueEvent{{
				Repository: "acme/app", Issue: 8, Event: "created", At: day,
			}})
			for call, err := range map[string]error{"LoadIssueEvents": loadErr, "AppendIssueEvents": appendErr} {
				var m *MalformedError
				if !errors.As(err, &m) || m.Line != c.line || !strings.Contains(m.Reason, c.reason) {
					t.Errorf("%s: want ErrMalformed at line %d saying %q, got %v", call, c.line, c.reason, err)
				}
			}
			assertUntouched(t, path, c.content)
		})
	}
}
