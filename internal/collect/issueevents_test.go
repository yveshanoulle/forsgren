package collect

import (
	"fmt"
	"path/filepath"
	"slices"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// allIssueJSON is an issue of acme/app as GitHub lists every issue: number,
// state, created at created, closed at closed (null when empty) and
// state_reason reason (null when empty), no labels.
func allIssueJSON(number int, state, created, closed, reason string) string {
	quoted := func(s string) string {
		if s == "" {
			return "null"
		}
		return fmt.Sprintf("%q", s)
	}
	return fmt.Sprintf(`{"id": %d, "number": %d, "title": "An issue", "state": %q, "labels": [], `+
		`"created_at": %q, "updated_at": %q, "closed_at": %s, "state_reason": %s, "body": null}`,
		7000+number, number, state, created, created, quoted(closed), quoted(reason))
}

// TestCollectStoresTheEventsOfEveryIssue (forsgren#76, step 4): every issue
// of the repository, whatever its labels, gives a created event at its
// creation and, when closed, a closed event at its closing with GitHub's
// reason, in data/issues.csv next to the history, oldest event first.
func TestCollectStoresTheEventsOfEveryIssue(t *testing.T) {
	g := issuesOnly(t, allIssueJSON(3, "open", "2026-09-20T08:00:00Z", "", ""),
		allIssueJSON(2, "closed", "2026-09-15T07:45:00Z", "2026-09-21T09:30:00Z", "not_planned"))
	path := historyPath(t)
	if r := g.collect(t, shop(production), path, 1); r.err != nil {
		t.Fatalf("want the run to succeed, got %v (stderr %q)", r.err, r.stderr)
	}
	got, err := history.LoadIssueEvents(filepath.Join(filepath.Dir(path), "issues.csv"))
	if err != nil {
		t.Fatalf("want an issues file, got %v", err)
	}
	want := []history.IssueEvent{
		{Repository: "acme/app", Issue: 2, Event: "created", At: at(15, 7, 45)},
		{Repository: "acme/app", Issue: 3, Event: "created", At: at(20, 8, 0)},
		{Repository: "acme/app", Issue: 2, Event: "closed", Reason: "not_planned", At: at(21, 9, 30)},
	}
	if !slices.Equal(got, want) {
		t.Errorf("want the events\n%v\ngot\n%v", want, got)
	}
}
