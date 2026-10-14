package collect

import (
	"errors"
	"fmt"
	"io/fs"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"strings"
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

// fullMarksBeside is the content of data/issues_full.csv next to the history
// at path, "" when there is none.
func fullMarksBeside(path string) string {
	raw, _ := os.ReadFile(filepath.Join(filepath.Dir(path), "issues_full.csv"))
	return string(raw)
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
		t.Run(name, func(t *testing.T) { wantARefusedListToFailTheRepositoryWhole(t, key) })
	}
}

// wantARefusedListToFailTheRepositoryWhole collects acme/app, whose deployment
// GitHub lists, while GitHub refuses the list that key names (a key of the
// fake's bodies): the run must fail and write no history.
func wantARefusedListToFailTheRepositoryWhole(t *testing.T, key string) {
	t.Helper()
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
}

// collectWithAnIssuesFileThatCannotBeWritten runs collect on acme/app, whose
// deployment and one open issue GitHub lists, with issues.csv read-only, and
// returns the history path. The run must fail.
func collectWithAnIssuesFileThatCannotBeWritten(t *testing.T) string {
	t.Helper()
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
	return path
}

// TestAnIssuesFileThatCannotBeWrittenStoresNoDeployment: when issues.csv
// cannot be written, the repository fails and its deployments are not stored
// either, so the next run reads them, and the issues, again.
func TestAnIssuesFileThatCannotBeWrittenStoresNoDeployment(t *testing.T) {
	path := collectWithAnIssuesFileThatCannotBeWritten(t)
	if _, err := os.Stat(path); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("want no history written, got %v", err)
	}
}

// TestAFailedStoreLeavesNoFullReadMark (forsgren#76, decision #109): when the
// events cannot be stored, the full read is not noted, so the next run does
// it again.
func TestAFailedStoreLeavesNoFullReadMark(t *testing.T) {
	path := collectWithAnIssuesFileThatCannotBeWritten(t)
	if got := fullMarksBeside(path); strings.Contains(got, "acme/app") {
		t.Errorf("want acme/app not in issues_full.csv, got %q", got)
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
	wantAFileOfAnotherVersionRefusedFirst(t, "issues", issuesFileBeside, "# forsgren issues v9\n")
}

// wantAFileOfAnotherVersionRefusedFirst writes content to the file that
// fileBeside names next to the history, collects, and fails unless the run
// fails with ErrUnknownVersion before GitHub is asked anything and the file
// stays as it was; name is the file's name in the messages.
func wantAFileOfAnotherVersionRefusedFirst(t *testing.T, name string, fileBeside func(string) string,
	content string,
) {
	t.Helper()
	g := newGitHub(t)
	path := historyPath(t)
	file := fileBeside(path)
	if err := os.MkdirAll(filepath.Dir(file), 0o750); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(file, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	r := g.collect(t, shop(production), path, 1)
	if !errors.Is(r.err, history.ErrUnknownVersion) || len(g.seen("/")) != 0 {
		t.Errorf("want ErrUnknownVersion before any request, got %v after %v", r.err, g.seen("/"))
	}
	if got, _ := os.ReadFile(filepath.Clean(file)); string(got) != content {
		t.Errorf("want the %s file untouched, got %q", name, got)
	}
}

// TestAnIssuesFullFileItCannotReadRefusesTheRun (forsgren#76, decision #109):
// an issues_full.csv with an unknown version or a malformed row is an error
// naming it, before GitHub is asked anything.
func TestAnIssuesFullFileItCannotReadRefusesTheRun(t *testing.T) {
	head := "# forsgren issues full v1\nrepository,full_at\n"
	for name, c := range map[string]struct {
		content string
		is      error
	}{
		"unknown version": {"# forsgren issues full v9\n", history.ErrUnknownVersion},
		"malformed row":   {head + "acme/app\n", history.ErrMalformed},
	} {
		t.Run(name, func(t *testing.T) {
			g := newGitHub(t)
			path := historyPath(t)
			writeBesideHistory(t, path, "issues_full.csv", c.content)
			r := g.collect(t, shop(production), path, 1)
			if !errors.Is(r.err, c.is) || !strings.Contains(r.err.Error(), "issues_full.csv") {
				t.Errorf("want %v naming issues_full.csv, got %v", c.is, r.err)
			}
			if got := g.seen("/"); len(got) != 0 {
				t.Errorf("want GitHub asked nothing, got %v", got)
			}
		})
	}
}

// wantClosedAgainOnce stores the events of #2, collects twice while GitHub
// says #2 is closed again at 28 Sep 16:00 as not planned, and fails unless
// each run leaves the stored events and exactly that one more closed event.
func wantClosedAgainOnce(t *testing.T, stored []history.IssueEvent) {
	t.Helper()
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list()
	g.bodies[allIssuesPath] = list(listed{
		number: 2, state: "closed", created: "2026-09-15T07:45:00Z", closed: "2026-09-28T16:00:00Z", reason: "not_planned",
	}.json())
	path := historyPath(t)
	issues := issuesFileBeside(path)
	if _, err := history.AppendIssueEvents(issues, stored); err != nil {
		t.Fatal(err)
	}
	want := append(stored, eventOfTwo("closed", "not_planned", at(28, 16, 0)))
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

// TestACloseAfterAReopenIsStoredOnceAtItsOwnTime (forsgren#76, decision
// #100): #2 was closed, reopened, and is closed again with a new closing time
// and reason: that is one more closed event at the new time and nothing else
// (no reopened event when the reopen fell between two runs and was never
// seen), and a second run over the same answer writes nothing.
func TestACloseAfterAReopenIsStoredOnceAtItsOwnTime(t *testing.T) {
	created := eventOfTwo("created", "", at(15, 7, 45))
	closed := eventOfTwo("closed", "completed", at(21, 9, 30))
	t.Run("the reopen was seen", func(t *testing.T) {
		wantClosedAgainOnce(t, []history.IssueEvent{created, closed, eventOfTwo("reopened", "", at(25, 0, 0))})
	})
	t.Run("the reopen was missed", func(t *testing.T) {
		wantClosedAgainOnce(t, []history.IssueEvent{created, closed})
	})
}

// TestACutListOfAllIssuesIsReported (forsgren#104, #76): when a page limit cuts
// the list of every issue, the daily read at the client's limit or the full
// read at its own, the newest pages are stored and stderr says what was not
// read, as it does for the failure issues.
func TestACutListOfAllIssuesIsReported(t *testing.T) {
	for name, c := range map[string]struct{ key, want string }{
		"daily read": {allIssuesPath,
			"collect: acme/app: read the newest 1 page(s) of issues only; older ones were not read\n"},
		"full read": {fullIssuesPath, "collect: acme/app: the full read stopped at 100 page(s) of issues; " +
			"the daily collection continues, but older issues and so the historical total stay incomplete\n"},
	} {
		t.Run(name, func(t *testing.T) {
			g := newGitHub(t)
			g.bodies[deploymentsPath] = list()
			g.bodies[c.key] = list(listed{number: 3, state: "open", created: "2026-09-20T08:00:00Z"}.json())
			g.paged[c.key] = true
			path := historyPath(t)
			r := g.collect(t, shop(production), path, 1)
			if r.err != nil || r.stderr != c.want {
				t.Errorf("want stderr %q and no error, got %q, %v", c.want, r.stderr, r.err)
			}
			got, err := history.LoadIssueEvents(issuesFileBeside(path))
			if err != nil || len(got) != 1 {
				t.Errorf("want the one issue read stored, got %v, %v", got, err)
			}
		})
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
	issues := issuesFileBeside(path)
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

// gitHubWithAnOldIssue is a GitHub where acme/app has no deployment and two
// closed issues: #2, recent, which the daily read lists, and #1, from 2025,
// which only the full read lists.
func gitHubWithAnOldIssue(t *testing.T) *gitHub {
	t.Helper()
	recent := listed{2, "closed", "2026-09-20T08:00:00Z", "2026-09-21T09:30:00Z", "completed"}.json()
	old := listed{1, "closed", "2025-01-10T08:00:00Z", "2025-02-01T09:00:00Z", "completed"}.json()
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list()
	g.bodies[allIssuesPath] = list(recent)
	g.bodies[fullIssuesPath] = list(recent, old)
	return g
}

// TestTheFullReadStoresTheHistoryTheDailyReadNeverSees (forsgren#76, decision
// #109): a repository with no full-read mark is read once without a since, so
// an old issue the daily read does not list gets its events, and the events
// already stored are not written again.
func TestTheFullReadStoresTheHistoryTheDailyReadNeverSees(t *testing.T) {
	g := gitHubWithAnOldIssue(t)
	path := historyPath(t)
	issues := issuesFileBeside(path)
	stored := []history.IssueEvent{
		eventOfTwo("created", "", at(20, 8, 0)), eventOfTwo("closed", "completed", at(21, 9, 30)),
	}
	if _, err := history.AppendIssueEvents(issues, stored); err != nil {
		t.Fatal(err)
	}
	if r := g.collect(t, shop(production), path, 1); r.err != nil {
		t.Fatalf("want the run to succeed, got %v (stderr %q)", r.err, r.stderr)
	}
	eventOfOne := func(event, reason string, created time.Time) history.IssueEvent {
		return history.IssueEvent{Repository: "acme/app", Issue: 1, Event: event, Reason: reason, At: created}
	}
	got, err := history.LoadIssueEvents(issues)
	want := append(stored,
		eventOfOne("created", "", time.Date(2025, time.January, 10, 8, 0, 0, 0, time.UTC)),
		eventOfOne("closed", "completed", time.Date(2025, time.February, 1, 9, 0, 0, 0, time.UTC)))
	if err != nil || !slices.Equal(got, want) {
		t.Errorf("want the events\n%v\ngot\n%v (%v)", want, got, err)
	}
}

// issuesFullFile is the content of issues_full.csv holding acme/app at when:
// per repository, when the one full read of its issues was done (forsgren#76,
// decision #109).
func issuesFullFile(when string) string {
	return "# forsgren issues full v1\nrepository,full_at\nacme/app," + when + "\n"
}

// writeBesideHistory writes content as the file name next to the history at
// path, creating the folder.
func writeBesideHistory(t *testing.T, path, name, content string) {
	t.Helper()
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o750); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, name), []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
}

// wantNoListWithoutSince fails when the fake saw a list of issues asked for
// without a since, which only the one full read does.
func wantNoListWithoutSince(t *testing.T, g *gitHub) {
	t.Helper()
	for _, request := range g.seen(issuesPath + "?") {
		if !strings.Contains(request, "since=") && !strings.Contains(request, "labels=") {
			t.Errorf("want no list of issues without a since, got %s", request)
		}
	}
}

// TestARepositoryWithAFullReadMarkIsNotReadInFullAgain (forsgren#76, decision
// #109): data/issues_full.csv holding acme/app says its whole history was
// read, so the run reads only the issues updated since its read mark: the
// old issue the full answer would add is not stored, and no list without a
// since is asked for.
func TestARepositoryWithAFullReadMarkIsNotReadInFullAgain(t *testing.T) {
	g := gitHubWithAnOldIssue(t)
	path := historyPath(t)
	writeBesideHistory(t, path, "issues_full.csv", issuesFullFile("2026-09-25T00:00:00Z"))
	if r := g.collect(t, shop(production), path, 1); r.err != nil {
		t.Fatalf("want the run to succeed, got %v (stderr %q)", r.err, r.stderr)
	}
	got, err := history.LoadIssueEvents(issuesFileBeside(path))
	want := []history.IssueEvent{eventOfTwo("created", "", at(20, 8, 0)), eventOfTwo("closed", "completed", at(21, 9, 30))}
	if err != nil || !slices.Equal(got, want) {
		t.Errorf("want only the recent issue's events\n%v\ngot\n%v (%v)", want, got, err)
	}
	wantNoListWithoutSince(t, g)
}

// fullMarkAfterAFullRead runs collect on acme/app, whose full read lists one
// open issue, with a next page every time when cut is set, and returns the
// content of issues_full.csv afterwards, "" when there is none.
func fullMarkAfterAFullRead(t *testing.T, cut bool) string {
	t.Helper()
	g := newGitHub(t)
	g.bodies[deploymentsPath] = list()
	g.bodies[fullIssuesPath] = list(listed{number: 3, state: "open", created: "2026-09-20T08:00:00Z"}.json())
	g.paged[fullIssuesPath] = cut
	path := historyPath(t)
	if r := g.collect(t, shop(production), path, 1); r.err != nil {
		t.Fatalf("want the run to succeed, got %v (stderr %q)", r.err, r.stderr)
	}
	return fullMarksBeside(path)
}

// TestACompleteFullReadLeavesItsMark (forsgren#76, decision #109): a run for a
// repository with no mark reads its issues in full and then notes it in
// data/issues_full.csv at the run's time, whole seconds, UTC.
func TestACompleteFullReadLeavesItsMark(t *testing.T) {
	if got, want := fullMarkAfterAFullRead(t, false), issuesFullFile("2026-10-01T00:00:00Z"); got != want {
		t.Errorf("want issues_full.csv\n%q\ngot\n%q", want, got)
	}
}

// TestACutFullReadLeavesNoMark (forsgren#76, decision #109): a full read that
// stopped at its page cap is not noted, so the next run reads in full again.
func TestACutFullReadLeavesNoMark(t *testing.T) {
	if got := fullMarkAfterAFullRead(t, true); strings.Contains(got, "acme/app") {
		t.Errorf("want acme/app not in issues_full.csv, got %q", got)
	}
}
