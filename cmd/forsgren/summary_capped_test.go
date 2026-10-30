package main

import "testing"

// The Collected words of a commit files read that stopped at the cap of a run
// (forsgren#589, step 2): planned, so the run stays complete, and the
// repository is named after complete, before the failure issues counted in
// the total only.

// TestRunSummaryNamesACappedCommitFilesReadAndStaysComplete: a capped
// repository is named with the 1000 read and the next runs continuing.
func TestRunSummaryNamesACappedCommitFilesReadAndStaysComplete(t *testing.T) {
	pinNow(t)
	report := reportHead + "complete\ncommit-files-capped acme/app\ncommit-files-capped acme/api\n"
	want := summaryOf(version, "up to date") + "- Collected: complete; " +
		"acme/app commit files: 1000 read this run, the next runs continue; " +
		"acme/api commit files: 1000 read this run, the next runs continue\n"
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
		"pulls-cut acme/api\ncommit-files-capped acme/app\nfailure-service acme/app 43 unknown Web\n"
	want := summaryOf(version, "up to date") + "- Collected: incomplete, budget reached; " +
		"acme/api pull requests cut short (deployments and issues read); resets 2026-10-01 11:00 UTC; " +
		"acme/app commit files: 1000 read this run, the next runs continue; " +
		"failure issue #43 of acme/app: service \"Web\" is unknown, so the failure was counted in the total only\n"
	if got := collectedSummary(t, report, false); got != want {
		t.Errorf("want %q, got %q", want, got)
	}
}
