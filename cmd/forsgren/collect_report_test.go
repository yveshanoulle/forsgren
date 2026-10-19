package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// reportFile is the file --cut-report names, in a fresh directory.
func reportFile(t *testing.T) string { return filepath.Join(t.TempDir(), "collect-report") }

// TestCollectWritesACompleteReport (forsgren#64, step 3b): with --cut-report a
// run that cut no repository short writes the report file saying complete.
func TestCollectWritesACompleteReport(t *testing.T) {
	t.Setenv("FORSGREN_TOKEN", testToken)
	fakeAPI(t, acmeApp, 0)
	file := reportFile(t)
	got := collectOneRepository(t, "--cut-report", file)
	content, err := os.ReadFile(filepath.Clean(file))
	if want := "# forsgren collect report v1\ncomplete\n"; got.code != 0 || err != nil || string(content) != want {
		t.Errorf("want exit 0 and %q, got %+v, %q and %v", want, got, content, err)
	}
}

// TestAFailedCollectLeavesNoReportFromAnEarlierRun: the file is removed first
// thing, so a collect that fails early (no token) leaves none, and the job
// summary reads unknown, never an old run's report.
func TestAFailedCollectLeavesNoReportFromAnEarlierRun(t *testing.T) {
	t.Setenv("FORSGREN_TOKEN", "")
	file := reportFile(t)
	if err := os.WriteFile(file, []byte("# forsgren collect report v1\ncomplete\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if got := collectOneRepository(t, "--cut-report", file); got.code != 1 {
		t.Fatalf("want exit 1, got %+v", got)
	}
	if _, err := os.Stat(file); err == nil {
		t.Error("want the stale report removed, it is still there")
	}
}

// TestCollectFailsWhenTheReportCannotBeWritten: a report that cannot be
// written is exit 1 with collect's own message, not silence.
func TestCollectFailsWhenTheReportCannotBeWritten(t *testing.T) {
	t.Setenv("FORSGREN_TOKEN", testToken)
	fakeAPI(t, acmeApp, 0)
	got := collectOneRepository(t, "--cut-report", filepath.Join(t.TempDir(), "missing", "report"))
	if got.code != 1 || !strings.HasPrefix(got.stderr, "collect: ") {
		t.Errorf("want exit 1 and collect's message, got %+v", got)
	}
}

// TestCollectFailsWhenAStaleReportCannotBeRemoved: a report that cannot be
// removed is exit 1 with collect's own message, not silence.
func TestCollectFailsWhenAStaleReportCannotBeRemoved(t *testing.T) {
	t.Setenv("FORSGREN_TOKEN", testToken)
	fakeAPI(t, acmeApp, 0)
	got := collectOneRepository(t, "--cut-report", nonEmptyDir(t))
	if got.code != 1 || !strings.HasPrefix(got.stderr, "collect: ") {
		t.Errorf("want exit 1 and collect's message, got %+v", got)
	}
}
