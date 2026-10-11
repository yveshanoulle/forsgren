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
	"time"

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

// issuesFileBeside is data/issues.csv next to the history at path.
func issuesFileBeside(path string) string { return filepath.Join(filepath.Dir(path), "issues.csv") }

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
	got, err := history.LoadIssueEvents(issuesFileBeside(path))
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
// list of every issue, the daily read or the full one (the failure issues are
// fine), the repository is stored not at all, its deployments neither.
func TestARefusedListOfAllIssuesFailsTheRepositoryWhole(t *testing.T) {
	for name, key := range map[string]string{"daily read": allIssuesPath, "full read": fullIssuesPath} {
		t.Run(name, func(t *testing.T) {
			g := newGitHub(t)
			g.bodies[deploymentsPath] = list(deployment(1001, shaA, "deploy", "2026-09-21T10:00:00Z"))
			g.bodies[statusesPath("1001")] = list(status(6, "success", "2026-09-21T10:05:00Z"))
			g.bodies[key] = `{"message": "Server Error"}`
			g.status[key] = http.StatusInternalServerError
			path := historyPath(t)
			r := g.collect(t, shop(production), path, 1)
			if !errors.Is(r.err, ErrFailed) {
				t.Errorf("want the repository failed, got %v, %q", r.err, r.stderr)
			}
			if _, err := os.Stat(path); !errors.Is(err, fs.ErrNotExist) {
				t.Errorf("want no history written, got %v", err)
			}
		})
	}
}

// TestAnIssuesFileThatCannotBeWrittenStoresNoDeployment: when issues.csv
// cannot be written, the repository fails and its deployments are not stored
// either, so the next run reads them, and the issues, again.
func TestAnIssuesFileThatCannotBeWrittenStoresNoDeployment(t *testing.T) {
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list(deployment(1001, shaA, "deploy", "2026-09-21T10:00:00Z"))
	g.bodies[statusesPath("1001")] = list(status(6, "success", "2026-09-21T10:05:00Z"))
	g.bodies[allIssuesPath] = list(listed{number: 3, state: "open", created: "2026-09-20T08:00:00Z"}.json())
	path := historyPath(t)
	issues := issuesFileBeside(path)
	if _, err := history.AppendIssueEvents(issues, nil); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(issues, 0o400); err != nil {
		t.Fatal(err)
	}
	if r := g.collect(t, shop(production), path, 1); !errors.Is(r.err, ErrFailed) {
		t.Fatalf("want the run to fail on a read-only issues file, got %v (stderr %q)", r.err, r.stderr)
	}
	if _, err := os.Stat(path); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("want no history written, got %v", err)
	}
}

// TestAReopenedIssueGetsOneReopenedEventAtTheRunTime (forsgren#76, decision
// #100): GitHub gives no reopen time, so an issue that is open while its
// last stored event is a close gets a reopened event at the run's time, and
// its created and closed events are not written again.
func TestAReopenedIssueGetsOneReopenedEventAtTheRunTime(t *testing.T) {
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list()
	g.bodies[allIssuesPath] = list(
		listed{number: 2, state: "open", created: "2026-09-15T07:45:00Z", reason: "reopened"}.json())
	path := historyPath(t)
	issues := issuesFileBeside(path)
	stored := []history.IssueEvent{
		{Repository: "acme/app", Issue: 2, Event: "created", At: at(15, 7, 45)},
		{Repository: "acme/app", Issue: 2, Event: "closed", Reason: "completed", At: at(21, 9, 30)},
	}
	if _, err := history.AppendIssueEvents(issues, stored); err != nil {
		t.Fatal(err)
	}
	if r := g.collect(t, shop(production), path, 1); r.err != nil {
		t.Fatalf("want the run to succeed, got %v (stderr %q)", r.err, r.stderr)
	}
	got, err := history.LoadIssueEvents(issues)
	if err != nil {
		t.Fatalf("want an issues file, got %v", err)
	}
	want := append(stored, history.IssueEvent{Repository: "acme/app", Issue: 2, Event: "reopened", At: now})
	if !slices.Equal(got, want) {
		t.Errorf("want the events\n%v\ngot\n%v", want, got)
	}
}

// TestAnIssuesFileItCannotReadIsRefusedFirst: a malformed issues file fails
// the run before GitHub is asked anything, and stays as it was.
func TestAnIssuesFileItCannotReadIsRefusedFirst(t *testing.T) {
	g := newGitHub(t)
	path := historyPath(t)
	issues := issuesFileBeside(path)
	if err := os.MkdirAll(filepath.Dir(issues), 0o750); err != nil {
		t.Fatal(err)
	}
	content := "# forsgren issues v9\n"
	if err := os.WriteFile(issues, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	r := g.collect(t, shop(production), path, 1)
	if !errors.Is(r.err, history.ErrUnknownVersion) || len(g.seen("/")) != 0 {
		t.Errorf("want ErrUnknownVersion before any request, got %v after %v", r.err, g.seen("/"))
	}
	if got, _ := os.ReadFile(filepath.Clean(issues)); string(got) != content {
		t.Errorf("want the issues file untouched, got %q", got)
	}
}

// TestACloseAfterAReopenIsStoredOnceAtItsOwnTime (forsgren#76): #2 was
// closed, reopened, and is closed again with a new closing time and reason:
// that is one more closed event at the new time and nothing else, and a
// second run over the same answer writes nothing.
func TestACloseAfterAReopenIsStoredOnceAtItsOwnTime(t *testing.T) {
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list()
	g.bodies[allIssuesPath] = list(listed{
		number: 2, state: "closed", created: "2026-09-15T07:45:00Z", closed: "2026-09-28T16:00:00Z", reason: "not_planned",
	}.json())
	path := historyPath(t)
	issues := issuesFileBeside(path)
	stored := []history.IssueEvent{
		{Repository: "acme/app", Issue: 2, Event: "created", At: at(15, 7, 45)},
		{Repository: "acme/app", Issue: 2, Event: "closed", Reason: "completed", At: at(21, 9, 30)},
		{Repository: "acme/app", Issue: 2, Event: "reopened", At: at(25, 0, 0)},
	}
	if _, err := history.AppendIssueEvents(issues, stored); err != nil {
		t.Fatal(err)
	}
	want := append(stored, history.IssueEvent{
		Repository: "acme/app", Issue: 2, Event: "closed", Reason: "not_planned", At: at(28, 16, 0),
	})
	for run := 1; run <= 2; run++ {
		if r := g.collect(t, shop(production), path, 1); r.err != nil {
			t.Fatalf("run %d: want it to succeed, got %v (stderr %q)", run, r.err, r.stderr)
		}
		got, err := history.LoadIssueEvents(issues)
		if err != nil || !slices.Equal(got, want) {
			t.Errorf("run %d: want the events\n%v\ngot\n%v (%v)", run, want, got, err)
		}
	}
}

// TestACutListOfAllIssuesIsReported (forsgren#104): when the page limit cuts
// the list of every issue, the newest pages are stored and stderr says older
// issues were not read, as it does for the failure issues.
func TestACutListOfAllIssuesIsReported(t *testing.T) {
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list()
	g.bodies[allIssuesPath] = list(listed{number: 3, state: "open", created: "2026-09-20T08:00:00Z"}.json())
	g.paged[allIssuesPath] = true
	path := historyPath(t)
	r := g.collect(t, shop(production), path, 1)
	want := "collect: acme/app: read the newest 1 page(s) of issues only; older ones were not read\n"
	if r.err != nil || r.stderr != want {
		t.Errorf("want stderr %q and no error, got %q, %v", want, r.stderr, r.err)
	}
	got, err := history.LoadIssueEvents(filepath.Join(filepath.Dir(path), "issues.csv"))
	if err != nil || len(got) != 1 {
		t.Errorf("want the one issue read stored, got %v, %v", got, err)
	}
}

// wantReopenedAfter stores the events of acme/app#2 one append at a time, so
// the file holds them in this order whatever their times, collects while
// GitHub says the issue is open, and fails unless exactly one reopened event
// at the run's time was added.
func wantReopenedAfter(t *testing.T, stored ...history.IssueEvent) {
	t.Helper()
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list()
	g.bodies[allIssuesPath] = list(
		listed{number: 2, state: "open", created: "2026-09-15T07:45:00Z", reason: "reopened"}.json())
	path := historyPath(t)
	issues := filepath.Join(filepath.Dir(path), "issues.csv")
	for _, event := range stored {
		if _, err := history.AppendIssueEvents(issues, []history.IssueEvent{event}); err != nil {
			t.Fatal(err)
		}
	}
	if r := g.collect(t, shop(production), path, 1); r.err != nil {
		t.Fatalf("want the run to succeed, got %v (stderr %q)", r.err, r.stderr)
	}
	got, err := history.LoadIssueEvents(issues)
	want := append(stored, history.IssueEvent{Repository: "acme/app", Issue: 2, Event: "reopened", At: now})
	if err != nil || !slices.Equal(got, want) {
		t.Errorf("want the events\n%v\ngot\n%v (%v)", want, got, err)
	}
}

// eventOfTwo is an event of acme/app#2 at at, with reason.
func eventOfTwo(event, reason string, when time.Time) history.IssueEvent {
	return history.IssueEvent{Repository: "acme/app", Issue: 2, Event: event, Reason: reason, At: when}
}

// TestTheLastEventOfAnIssueIsTheNewestNotTheLastLine (forsgren#76, decision
// #109): a later append can put an older event after a newer one in the file
// (an older created line after the closed line), and the issue's last event is
// still the newest by time, so an issue that is open again gets its reopened
// event.
func TestTheLastEventOfAnIssueIsTheNewestNotTheLastLine(t *testing.T) {
	wantReopenedAfter(t, eventOfTwo("closed", "completed", at(21, 9, 30)), eventOfTwo("created", "", at(15, 7, 45)))
}

// TestTheLastEventAtTheSameSecondFollowsTheEventOrder (forsgren#76, decision
// #109): an issue created and closed in the same second has the close as its
// last event whatever the order of the lines, created before closed before
// reopened.
func TestTheLastEventAtTheSameSecondFollowsTheEventOrder(t *testing.T) {
	wantReopenedAfter(t, eventOfTwo("closed", "completed", at(15, 7, 45)), eventOfTwo("created", "", at(15, 7, 45)))
}

// TestTheFullReadStoresTheHistoryTheDailyReadNeverSees (forsgren#76, decision
// #109): a repository with no full-read mark is read once without a since, so
// an old issue the daily read does not list gets its events, and the events
// already stored are not written again.
func TestTheFullReadStoresTheHistoryTheDailyReadNeverSees(t *testing.T) {
	recent := listed{2, "closed", "2026-09-20T08:00:00Z", "2026-09-21T09:30:00Z", "completed"}.json()
	old := listed{1, "closed", "2025-01-10T08:00:00Z", "2025-02-01T09:00:00Z", "completed"}.json()
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list()
	g.bodies[allIssuesPath] = list(recent)
	g.bodies[fullIssuesPath] = list(recent, old)
	path := historyPath(t)
	issues := filepath.Join(filepath.Dir(path), "issues.csv")
	held := []history.IssueEvent{
		eventOfTwo("created", "", at(20, 8, 0)), eventOfTwo("closed", "completed", at(21, 9, 30)),
	}
	if _, err := history.AppendIssueEvents(issues, held); err != nil {
		t.Fatal(err)
	}
	if r := g.collect(t, shop(production), path, 1); r.err != nil {
		t.Fatalf("want the run to succeed, got %v (stderr %q)", r.err, r.stderr)
	}
	eventOfOne := func(event, reason string, created time.Time) history.IssueEvent {
		return history.IssueEvent{Repository: "acme/app", Issue: 1, Event: event, Reason: reason, At: created}
	}
	got, err := history.LoadIssueEvents(issues)
	want := append(held,
		eventOfOne("created", "", time.Date(2025, time.January, 10, 8, 0, 0, 0, time.UTC)),
		eventOfOne("closed", "completed", time.Date(2025, time.February, 1, 9, 0, 0, 0, time.UTC)))
	if err != nil || !slices.Equal(got, want) {
		t.Errorf("want the events\n%v\ngot\n%v (%v)", want, got, err)
	}
}
