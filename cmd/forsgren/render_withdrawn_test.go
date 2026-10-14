package main

import (
	"path/filepath"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// withdrawnAt is when the withdrawals of these tests were noted.
var withdrawnAt = time.Date(2026, 10, 2, 0, 0, 0, 0, time.UTC)

// withdraw is the withdrawal of failure issue number of repository, for a
// lost label; reinstate is the line that takes it back.
func withdraw(repository string, number int64) history.Withdrawal {
	return history.Withdrawal{Repository: repository, Issue: number, Withdrawn: true,
		Reason: history.ReasonLabelRemoved, At: withdrawnAt}
}

func reinstate(repository string, number int64) history.Withdrawal {
	return history.Withdrawal{Repository: repository, Issue: number, At: withdrawnAt.Add(time.Hour)}
}

// renderedWith is the page rendered for acmeHistory, the failures and, when
// there are any, the withdrawals stored in order, one write each.
func renderedWith(t *testing.T, failures []history.Failure, withdrawals ...history.Withdrawal) string {
	t.Helper()
	data := writeHistory(t, acmeHistory())
	writeFailures(t, data, failures)
	for _, w := range withdrawals {
		file := filepath.Join(filepath.Dir(data), "failures_withdrawn.csv")
		if _, err := history.AppendWithdrawals(file, []history.Withdrawal{w}); err != nil {
			t.Fatal(err)
		}
	}
	code, stderr, index := renderWith(t, "--config", writeAllPagesConfig(t, validConfig), "--data", data)
	if code != 0 {
		t.Fatalf("want exit 0, got %d (stderr %q)", code, stderr)
	}
	return index
}

// withoutIOS7 is acmeFailures less acme/ios-app's issue 7.
func withoutIOS7() []history.Failure {
	all := acmeFailures()
	return append(all[:1:1], all[2:]...)
}

// TestRenderLeavesOutAWithdrawnFailure (forsgren#155, step 5): a failure
// issue withdrawn in data/failures_withdrawn.csv no longer counts in change
// fail rate, as if it were not in failures.csv; one reinstated by a later
// line counts again, and without a withdrawn file all count.
func TestRenderLeavesOutAWithdrawnFailure(t *testing.T) {
	pinNow(t)
	all := renderedWith(t, acmeFailures())
	without := renderedWith(t, withoutIOS7())
	if all == without {
		t.Fatal("want one failure issue to change the page, or this test proves nothing")
	}
	if got := renderedWith(t, acmeFailures(), withdraw("acme/ios-app", 7)); got != without {
		t.Errorf("want the withdrawn issue left out\n--- got ---\n%s\n--- want ---\n%s", got, without)
	}
	if got := renderedWith(t, acmeFailures(), withdraw("acme/ios-app", 7), reinstate("acme/ios-app", 7)); got != all {
		t.Errorf("want the reinstated issue to count again\n--- got ---\n%s\n--- want ---\n%s", got, all)
	}
}

// TestWithdrawnFailuresDoNotChangeRecoveryTime: recovery time reads the
// deployments only, so with every failure issue withdrawn the page is the one
// of TestRenderShowsRecoveryTime, golden and all.
func TestWithdrawnFailuresDoNotChangeRecoveryTime(t *testing.T) {
	pinNow(t)
	records := append(acmeHistory(),
		shipped(10, "acme/api", history.StateFailure, "2026-09-26T10:00:00Z"),
		shipped(11, "acme/ios-app", history.StateFailure, "2026-09-30T04:00:00Z"))
	data := writeHistory(t, records)
	writeFailures(t, data, acmeFailures())
	var all []history.Withdrawal
	for _, f := range acmeFailures() {
		all = append(all, withdraw(f.Repository, f.Issue))
	}
	if _, err := history.AppendWithdrawals(filepath.Join(filepath.Dir(data), "failures_withdrawn.csv"), all); err != nil {
		t.Fatal(err)
	}
	wantGolden(t, "index.recovery.golden.html", "--config", writeAllPagesConfig(t, validConfig), "--data", data)
}

// TestRenderRefusesABadWithdrawnFile: a malformed or unknown-version withdrawn
// file fails render with its own message, naming it, and writes nothing.
func TestRenderRefusesABadWithdrawnFile(t *testing.T) {
	head := "# forsgren failures withdrawn v1\nrepository,issue,withdrawn,reason,at\n"
	wantBadFileRefused(t, "failures_withdrawn.csv", map[string]badFile{
		"unknown version": {"# forsgren failures withdrawn v9\n", "unknown history format version"},
		"malformed line":  {head + "acme/api,41\n", "line 3: malformed history"},
	})
}
