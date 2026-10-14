package collect

import (
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// withdrawnFileBeside is data/failures_withdrawn.csv next to the history at
// path.
func withdrawnFileBeside(path string) string {
	return filepath.Join(filepath.Dir(path), "failures_withdrawn.csv")
}

// TestAFailureIssueThatLostItsLabelIsWithdrawn (forsgren#155, step 1): issue
// 42 was stored as a failure; the next run's daily read of every issue lists
// it without the failure label, and the failure query no longer returns it.
// The failures file keeps its line, and data/failures_withdrawn.csv gets a
// new one that withdraws it, for the reason label_removed.
func TestAFailureIssueThatLostItsLabelIsWithdrawn(t *testing.T) {
	g := issuesOnly(t, issueJSON(42, "2026-09-20T08:00:00Z", "", recordBlock))
	path := historyPath(t)
	g.collect(t, shop(production), path, 1)
	g.bodies[issuesPath] = list()
	g.bodies[allIssuesPath] = list(listed{number: 42, state: "open", created: "2026-09-20T08:00:00Z"}.json())
	if r := g.collect(t, shop(production), path, 1); r.err != nil {
		t.Fatalf("want the run to succeed, got %v (stderr %q)", r.err, r.stderr)
	}
	wantFailures(t, path, failure(42, at(20, 8, 0), time.Time{}, at(20, 7, 12)))
	got, err := history.LoadWithdrawals(withdrawnFileBeside(path))
	if err != nil {
		t.Fatalf("want a failures_withdrawn file, got %v", err)
	}
	want := []history.Withdrawal{{Repository: "acme/app", Issue: 42, Withdrawn: true, Reason: "label_removed", At: now}}
	if !slices.Equal(got, want) {
		t.Errorf("want the withdrawals\n%v\ngot\n%v", want, got)
	}
}

// TestOnlyAStoredFailureWithoutItsLabelIsWithdrawn (forsgren#155): the label
// is compared ignoring case, a stored issue that still has it is not
// withdrawn, and an issue never stored as a failure is none of this file's
// business, whatever its labels.
func TestOnlyAStoredFailureWithoutItsLabelIsWithdrawn(t *testing.T) {
	g := issuesOnly(t, issueJSON(42, "2026-09-20T08:00:00Z", "", recordBlock))
	path := historyPath(t)
	g.collect(t, shop(production), path, 1)
	g.bodies[issuesPath] = list()
	still := listed{number: 42, state: "open", created: "2026-09-20T08:00:00Z"}.json()
	still = strings.Replace(still, `"labels": []`, `"labels": [{"name": "bug"}, {"name": "Failure"}]`, 1)
	g.bodies[allIssuesPath] = list(still,
		listed{number: 9, state: "open", created: "2026-09-21T08:00:00Z"}.json())
	if r := g.collect(t, shop(production), path, 1); r.err != nil {
		t.Fatalf("want the run to succeed, got %v (stderr %q)", r.err, r.stderr)
	}
	if got, err := history.LoadWithdrawals(withdrawnFileBeside(path)); err != nil || len(got) != 0 {
		t.Errorf("want no withdrawal, got %v, %v", got, err)
	}
}

// TestAWithdrawnFileThatCannotBeWrittenStoresNoDeployment: when
// failures_withdrawn.csv cannot be written the repository fails and its
// deployments are not stored, so the next run reads them again.
func TestAWithdrawnFileThatCannotBeWrittenStoresNoDeployment(t *testing.T) {
	g := issuesOnly(t, issueJSON(42, "2026-09-20T08:00:00Z", "", recordBlock))
	path := historyPath(t)
	g.collect(t, shop(production), path, 1)
	withdrawn := withdrawnFileBeside(path)
	if err := os.Chmod(withdrawn, 0o400); err != nil {
		t.Fatal(err)
	}
	g.bodies[issuesPath] = list()
	g.bodies[allIssuesPath] = list(listed{number: 42, state: "open", created: "2026-09-20T08:00:00Z"}.json())
	g.bodies[deploymentsPath] = list(deployment(1001, shaA, "deploy", "2026-09-21T10:00:00Z"))
	g.bodies[statusesPath("1001")] = list(status(6, "success", "2026-09-21T10:05:00Z"))
	if r := g.collect(t, shop(production), path, 1); !errors.Is(r.err, ErrFailed) {
		t.Fatalf("want the run to fail on a read-only withdrawn file, got %v (stderr %q)", r.err, r.stderr)
	}
	wantRecords(t, path)
}

// TestAFailureIssueClosedAsNotPlannedIsWithdrawn (forsgren#155, step 2): issue
// 42 was stored open; the next run's daily read lists it still labelled
// failure, closed with state_reason not_planned. It is withdrawn, for the
// reason not_planned; a failure closed as completed is not.
func TestAFailureIssueClosedAsNotPlannedIsWithdrawn(t *testing.T) {
	g := issuesOnly(t, issueJSON(42, "2026-09-20T08:00:00Z", "", recordBlock),
		issueJSON(43, "2026-09-20T09:00:00Z", "", recordBlock))
	path := historyPath(t)
	g.collect(t, shop(production), path, 1)
	labelled := func(l listed) string {
		return strings.Replace(l.json(), `"labels": []`, `"labels": [{"name": "failure"}]`, 1)
	}
	g.bodies[allIssuesPath] = list(
		labelled(listed{42, "closed", "2026-09-20T08:00:00Z", "2026-09-21T09:30:00Z", "not_planned"}),
		labelled(listed{43, "closed", "2026-09-20T09:00:00Z", "2026-09-21T09:30:00Z", "completed"}))
	if r := g.collect(t, shop(production), path, 1); r.err != nil {
		t.Fatalf("want the run to succeed, got %v (stderr %q)", r.err, r.stderr)
	}
	got, err := history.LoadWithdrawals(withdrawnFileBeside(path))
	want := []history.Withdrawal{{Repository: "acme/app", Issue: 42, Withdrawn: true, Reason: "not_planned", At: now}}
	if err != nil || !slices.Equal(got, want) {
		t.Errorf("want the withdrawals\n%v\ngot\n%v (%v)", want, got, err)
	}
}

// TestAWithdrawnFailureThatGetsItsLabelBackIsReinstated (forsgren#155, step 3):
// issue 42 is stored, loses its label (withdrawn), gets it back (a
// withdrawn=false line), and a run that finds nothing new writes no line: not
// a second withdrawal while the label is off, not a second reinstatement.
func TestAWithdrawnFailureThatGetsItsLabelBackIsReinstated(t *testing.T) {
	g := issuesOnly(t, issueJSON(42, "2026-09-20T08:00:00Z", "", recordBlock))
	path := historyPath(t)
	g.collect(t, shop(production), path, 1)
	bare := listed{number: 42, state: "open", created: "2026-09-20T08:00:00Z"}.json()
	labelled := strings.Replace(bare, `"labels": []`, `"labels": [{"name": "failure"}]`, 1)
	linesAfter := func(body string) string {
		g.bodies[allIssuesPath] = list(body)
		if r := g.collect(t, shop(production), path, 1); r.err != nil {
			t.Fatalf("want the run to succeed, got %v (stderr %q)", r.err, r.stderr)
		}
		raw, _ := os.ReadFile(filepath.Clean(withdrawnFileBeside(path)))
		return string(raw)
	}
	head := "# forsgren failures withdrawn v1\nrepository,issue,withdrawn,reason,at\n"
	out := head + "acme/app,42,true,label_removed,2026-10-01T00:00:00Z\n"
	back := out + "acme/app,42,false,,2026-10-01T00:00:00Z\n"
	for i, step := range []struct{ body, want string }{
		{bare, out}, {bare, out}, {labelled, back}, {labelled, back},
	} {
		if got := linesAfter(step.body); got != step.want {
			t.Fatalf("run %d: want the file\n%q\ngot\n%q", i+1, step.want, got)
		}
	}
}

// TestAWithdrawnFileItCannotReadIsRefusedFirst: a withdrawn file of an unknown
// version fails the run before GitHub is asked anything, and stays as it was.
func TestAWithdrawnFileItCannotReadIsRefusedFirst(t *testing.T) {
	g := newGitHub(t)
	path := historyPath(t)
	withdrawn := withdrawnFileBeside(path)
	if err := os.MkdirAll(filepath.Dir(withdrawn), 0o750); err != nil {
		t.Fatal(err)
	}
	content := "# forsgren failures withdrawn v9\n"
	if err := os.WriteFile(withdrawn, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	r := g.collect(t, shop(production), path, 1)
	if !errors.Is(r.err, history.ErrUnknownVersion) || len(g.seen("/")) != 0 {
		t.Errorf("want ErrUnknownVersion before any request, got %v after %v", r.err, g.seen("/"))
	}
	if got, _ := os.ReadFile(filepath.Clean(withdrawn)); string(got) != content {
		t.Errorf("want the withdrawn file untouched, got %q", got)
	}
}
