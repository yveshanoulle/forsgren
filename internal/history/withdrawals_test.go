package history

import (
	"errors"
	"os"
	"path/filepath"
	"slices"
	"testing"
	"time"
)

var withdrawnAt = time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC)

func withdrawal(issue int64, withdrawn bool, reason string) Withdrawal {
	return Withdrawal{Repository: "acme/app", Issue: issue, Withdrawn: withdrawn, Reason: reason, At: withdrawnAt}
}

// wantWrote fails unless appending w to the file at path writes n lines.
func wantWrote(t *testing.T, path string, w Withdrawal, n int) {
	t.Helper()
	if got, err := AppendWithdrawals(path, []Withdrawal{w}); err != nil || got != n {
		t.Fatalf("want %d line(s) written, got %d, %v", n, got, err)
	}
}

// TestAWithdrawalIsWrittenOnceAndReinstatedByANewLine (forsgren#155): the
// file is created with its version, an unchanged state is not written again,
// a changed one is a new line, and the newest line of an issue is the issue.
func TestAWithdrawalIsWrittenOnceAndReinstatedByANewLine(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data", "failures_withdrawn.csv")
	wantWrote(t, path, withdrawal(42, true, ReasonLabelRemoved), 1)
	wantWrote(t, path, withdrawal(42, true, ReasonLabelRemoved), 0)
	wantWrote(t, path, withdrawal(42, false, ""), 1)
	got, err := LoadWithdrawals(path)
	if err != nil || !slices.Equal(got, []Withdrawal{withdrawal(42, false, "")}) {
		t.Errorf("want the reinstated issue as its newest line, got %v, %v", got, err)
	}
	raw, _ := os.ReadFile(filepath.Clean(path))
	want := "# forsgren failures withdrawn v1\nrepository,issue,withdrawn,reason,at\n" +
		"acme/app,42,true,label_removed,2026-10-01T00:00:00Z\nacme/app,42,false,,2026-10-01T00:00:00Z\n"
	if string(raw) != want {
		t.Errorf("want the file\n%q\ngot\n%q", want, raw)
	}
}

// TestAMalformedWithdrawalIsRefused: each bad line is named and nothing is written.
func TestAMalformedWithdrawalIsRefused(t *testing.T) {
	head := "# forsgren failures withdrawn v1\nrepository,issue,withdrawn,reason,at\n"
	for name, line := range map[string]string{
		"withdrawn": "acme/app,42,maybe,label_removed,2026-10-01T00:00:00Z\n",
		"issue":     "acme/app,x,true,label_removed,2026-10-01T00:00:00Z\n",
		"at":        "acme/app,42,true,label_removed,\n",
	} {
		path := filepath.Join(t.TempDir(), "w.csv")
		if err := os.WriteFile(path, []byte(head+line), 0o600); err != nil {
			t.Fatal(err)
		}
		var m *MalformedError
		if _, err := LoadWithdrawals(path); !errors.As(err, &m) {
			t.Errorf("%s: want a MalformedError, got %v", name, err)
		}
	}
	bad := []Withdrawal{withdrawal(42, true, "because"), withdrawal(42, true, ""), withdrawal(42, false, ReasonNotPlanned),
		{Repository: "acme/app", Issue: 42}, {Repository: "no", Issue: 1, At: withdrawnAt}}
	for _, w := range bad {
		if _, err := AppendWithdrawals(filepath.Join(t.TempDir(), "w.csv"), []Withdrawal{w}); err == nil {
			t.Errorf("want %v refused", w)
		}
	}
}

// TestNewWithdrawalsAreWrittenByRepositoryThenIssue: two in one call, given
// out of order, are appended in order.
func TestNewWithdrawalsAreWrittenByRepositoryThenIssue(t *testing.T) {
	path := filepath.Join(t.TempDir(), "w.csv")
	in := []Withdrawal{withdrawal(43, true, ReasonNotPlanned), withdrawal(42, true, ReasonLabelRemoved)}
	if n, err := AppendWithdrawals(path, in); err != nil || n != 2 {
		t.Fatalf("want 2 lines, got %d, %v", n, err)
	}
	got, err := LoadWithdrawals(path)
	if want := []Withdrawal{in[1], in[0]}; err != nil || !slices.Equal(got, want) {
		t.Errorf("want %v, got %v, %v", want, got, err)
	}
}

// TestWithoutWithdrawnDropsOnlyTheWithdrawnIssues (forsgren#155): a withdrawn
// issue goes, a reinstated one and one no line names stay, the repository
// compared ignoring case, the order kept.
func TestWithoutWithdrawnDropsOnlyTheWithdrawnIssues(t *testing.T) {
	failures := []Failure{
		{Repository: "acme/app", Issue: 1, OpenedAt: withdrawnAt},
		{Repository: "acme/app", Issue: 2, OpenedAt: withdrawnAt},
		{Repository: "acme/app", Issue: 3, OpenedAt: withdrawnAt},
	}
	got := WithoutWithdrawn(failures, []Withdrawal{
		{Repository: "ACME/app", Issue: 1, Withdrawn: true, Reason: ReasonLabelRemoved, At: withdrawnAt},
		{Repository: "acme/app", Issue: 2, At: withdrawnAt},
	})
	if want := failures[1:]; !slices.Equal(got, want) {
		t.Errorf("want %v, got %v", want, got)
	}
	if got := WithoutWithdrawn(failures, nil); !slices.Equal(got, failures) {
		t.Errorf("want nothing dropped without withdrawals, got %v", got)
	}
}
