package main

import "testing"

// The Collected words of a commit files read that stopped at the cap of a run
// (forsgren#589, step 2): planned, so the run stays complete, and the
// repository is named after complete, before the failure issues counted in
// the total only. Since forsgren#593 they say how far the read is, how many
// commits are left and about how many runs that takes.

// TestRunSummaryNamesACappedCommitFilesReadAndStaysComplete: a capped
// repository is named with the 1000 read, the commits read of all and those
// left, and the runs left rounded up, one run in the singular.
func TestRunSummaryNamesACappedCommitFilesReadAndStaysComplete(t *testing.T) {
	pinNow(t)
	report := reportHead + "complete\ncommit-files-capped acme/app read=4120 left=2340\n" +
		"commit-files-capped acme/api read=1000 left=1000\n"
	want := summaryOf(version, "up to date") + "- Collected: complete; " +
		"acme/app commit files: 1000 read this run, 4120 of 6460 read, 2340 left (about 3 more runs); " +
		"acme/api commit files: 1000 read this run, 1000 of 2000 read, 1000 left (about 1 more run)\n"
	if got := collectedSummary(t, report, false); got != want {
		t.Errorf("want %q, got %q", want, got)
	}
}

// TestRunSummaryKeepsTheOldCappedWordsForAReportWithoutCounts: a report
// written before forsgren#593 names the repository alone, and the words say
// what they said then.
func TestRunSummaryKeepsTheOldCappedWordsForAReportWithoutCounts(t *testing.T) {
	pinNow(t)
	report := reportHead + "complete\ncommit-files-capped acme/app\n"
	want := summaryOf(version, "up to date") + "- Collected: complete; " +
		"acme/app commit files: 1000 read this run, the next runs continue\n"
	if got := collectedSummary(t, report, false); got != want {
		t.Errorf("want %q, got %q", want, got)
	}
}

// TestRunSummaryKeepsTheCappedWordsAfterTheCutAndBeforeTheServiceWords: an
// incomplete run says its cut first, then the capped read, then the failure
// issue counted in the total only.
func TestRunSummaryKeepsTheCappedWordsAfterTheCutAndBeforeTheServiceWords(t *testing.T) {
	pinNow(t)
	report := reportHead + "incomplete resets=2026-10-01T11:00:00Z\n" +
		"pulls-cut acme/api\ncommit-files-capped acme/app read=1000 left=5\nfailure-service acme/app 43 unknown Web\n"
	want := summaryOf(version, "up to date") + "- Collected: incomplete, budget reached; " +
		"acme/api pull requests cut short (deployments and issues read); resets 2026-10-01 11:00 UTC; " +
		"acme/app commit files: 1000 read this run, 1000 of 1005 read, 5 left (about 1 more run); " +
		"failure issue #43 of acme/app: service \"Web\" is unknown, so the failure was counted in the total only\n"
	if got := collectedSummary(t, report, false); got != want {
		t.Errorf("want %q, got %q", want, got)
	}
}
