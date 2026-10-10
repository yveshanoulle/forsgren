package collect

import (
	"errors"
	"fmt"
	"io/fs"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// listed is an issue of acme/app as GitHub lists every issue: its number,
// state, creation time, closing time (empty while open) and state_reason
// (empty for none).
type listed struct {
	number                         int
	state, created, closed, reason string
}

// json is i as GitHub lists it, no labels; an empty closed time or reason is
// null.
func (i listed) json() string {
	quoted := func(s string) string {
		if s == "" {
			return "null"
		}
		return fmt.Sprintf("%q", s)
	}
	return fmt.Sprintf(`{"id": %d, "number": %d, "title": "An issue", "state": %q, "labels": [], `+
		`"created_at": %q, "updated_at": %q, "closed_at": %s, "state_reason": %s, "body": null}`,
		7000+i.number, i.number, i.state, i.created, i.created, quoted(i.closed), quoted(i.reason))
}

// TestCollectStoresTheEventsOfEveryIssue (forsgren#76, step 4): every issue
// of the repository, whatever its labels, gives a created event at its
// creation and, when closed, a closed event at its closing with GitHub's
// reason, in data/issues.csv next to the history, oldest event first.
func TestCollectStoresTheEventsOfEveryIssue(t *testing.T) {
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list()
	g.bodies[allIssuesPath] = list(
		listed{number: 3, state: "open", created: "2026-09-20T08:00:00Z"}.json(),
		listed{2, "closed", "2026-09-15T07:45:00Z", "2026-09-21T09:30:00Z", "not_planned"}.json())
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

// TestARefusedListOfAllIssuesFailsTheRepositoryWhole: when GitHub refuses the
// list of every issue (the failure issues are fine), the repository is
// stored not at all, its deployments neither.
func TestARefusedListOfAllIssuesFailsTheRepositoryWhole(t *testing.T) {
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list(deployment(1001, shaA, "deploy", "2026-09-21T10:00:00Z"))
	g.bodies[statusesPath("1001")] = list(status(6, "success", "2026-09-21T10:05:00Z"))
	g.bodies[allIssuesPath] = `{"message": "Server Error"}`
	g.status[allIssuesPath] = http.StatusInternalServerError
	path := historyPath(t)
	r := g.collect(t, shop(production), path, 1)
	if !errors.Is(r.err, ErrFailed) {
		t.Errorf("want the repository failed, got %v, %q", r.err, r.stderr)
	}
	if _, err := os.Stat(path); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("want no history written, got %v", err)
	}
}
