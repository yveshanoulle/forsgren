package main

import (
	"path/filepath"
	"testing"
)

// collectedSummary is the run summary with --collect-report naming a file
// that holds content, or, for a missing file, no file at all.
func collectedSummary(t *testing.T, content string, missing bool) string {
	t.Helper()
	file := filepath.Join(t.TempDir(), "collect-report")
	if !missing {
		writeFile(t, file, content)
	}
	code, stdout, stderr := runCommand("run-summary", "--latest", version, "--pr-check", "ok", "--collect-report", file)
	if code != 0 || stderr != "" {
		t.Fatalf("want exit 0 and no stderr, got %d, %q", code, stderr)
	}
	return stdout
}

const reportHead = "# forsgren collect report v1\n"

// TestRunSummaryTellsCollectedCompleteOnlyForACompleteReport (forsgren#64, step
// 3c, decision #238): a green run is not a complete history, so the summary
// has a Collected line, and says complete only for a report that says so.
func TestRunSummaryTellsCollectedCompleteOnlyForACompleteReport(t *testing.T) {
	pinNow(t)
	want := summaryOf(version, "up to date") + "- Collected: complete\n"
	if got := collectedSummary(t, reportHead+"complete\n", false); got != want {
		t.Errorf("want %q, got %q", want, got)
	}
}

// TestRunSummaryNamesWhatTheBudgetCutShort: each cut repository with how far
// it kept, that its issues were not read, the recent read when it was
// discarded, and a repository that made no progress named as such, then the
// time the budget resets.
func TestRunSummaryNamesWhatTheBudgetCutShort(t *testing.T) {
	pinNow(t)
	report := reportHead + "incomplete resets=2026-10-01T11:00:00Z\n" +
		"cut acme/app kept=2026-06-22 recent=read issues=unread progress=yes\n" +
		"cut acme/docs kept=none recent=discarded issues=unread progress=stalled\n" +
		"cut acme/api kept=none recent=kept issues=unread progress=no\n"
	want := summaryOf(version, "up to date") + "- Collected: incomplete, budget reached; " +
		"acme/app cut short (kept up to 2026-06-22, issues not read), " +
		"acme/docs cut short and not progressing (kept nothing, recent read discarded, issues not read), " +
		"acme/api cut short (kept the newest days, issues not read); resets 2026-10-01 11:00 UTC\n"
	if got := collectedSummary(t, report, false); got != want {
		t.Errorf("want %q, got %q", want, got)
	}
}

// TestRunSummaryNamesARepositoryWhosePullRequestsWereCutShort (forsgren#320,
// decision #307): a repository whose pull requests alone the budget cut
// short makes the run incomplete, never failed, named after the repositories
// cut short, with what it did read, then the time the budget resets.
func TestRunSummaryNamesARepositoryWhosePullRequestsWereCutShort(t *testing.T) {
	pinNow(t)
	for name, c := range map[string]struct{ cuts, words string }{
		"alone": {"", ""},
		"after a cut repository": {"cut acme/docs kept=none recent=discarded issues=unread progress=stalled\n",
			"acme/docs cut short and not progressing (kept nothing, recent read discarded, issues not read), "},
	} {
		t.Run(name, func(t *testing.T) {
			report := reportHead + "incomplete resets=2026-10-01T11:00:00Z\n" + c.cuts + "pulls-cut acme/app\n"
			want := summaryOf(version, "up to date") + "- Collected: incomplete, budget reached; " + c.words +
				"acme/app pull requests cut short (deployments and issues read); resets 2026-10-01 11:00 UTC\n"
			if got := collectedSummary(t, report, false); got != want {
				t.Errorf("want %q, got %q", want, got)
			}
		})
	}
}

// TestRunSummaryNamesTheRateLimitsApart:a repository that failed on GitHub's
// primary limit, its secondary limit or something else is named with which,
// and makes the run incomplete even when no repository was cut short.
func TestRunSummaryNamesTheRateLimitsApart(t *testing.T) {
	pinNow(t)
	report := reportHead + "complete\n" +
		"failed acme/web primary-rate-limit\n" +
		"failed acme/docs secondary-rate-limit\n" +
		"failed acme/api error\n"
	want := summaryOf(version, "up to date") + "- Collected: incomplete, " +
		"acme/web failed on GitHub's primary rate limit, " +
		"acme/docs failed on GitHub's secondary rate limit, " +
		"acme/api failed (see the collect step)\n"
	if got := collectedSummary(t, report, false); got != want {
		t.Errorf("want %q, got %q", want, got)
	}
}

// TestRunSummaryNeverCallsAMissingOrBrokenReportComplete: no file (collect
// failed before it ended, or was not asked) and a file that is no report are
// both unknown, each with its own words.
func TestRunSummaryNeverCallsAMissingOrBrokenReportComplete(t *testing.T) {
	pinNow(t)
	missing := summaryOf(version, "up to date") +
		"- Collected: unknown: collect wrote no report: see the failed collect step\n"
	if got := collectedSummary(t, "", true); got != missing {
		t.Errorf("want %q, got %q", missing, got)
	}
	broken := summaryOf(version, "up to date") +
		"- Collected: unknown: collect's report cannot be read: see the collect step\n"
	if got := collectedSummary(t, "complete\n", false); got != broken {
		t.Errorf("want %q, got %q", broken, got)
	}
}

// TestRunSummaryHasNoCollectedLineWithoutTheFlag: a caller that does not pass
// --collect-report gets the summary it always had.
func TestRunSummaryHasNoCollectedLineWithoutTheFlag(t *testing.T) {
	pinNow(t)
	_, stdout, _ := runCommand("run-summary", "--latest", version, "--pr-check", "ok")
	if want := summaryOf(version, "up to date"); stdout != want {
		t.Errorf("want %q, got %q", want, stdout)
	}
}
