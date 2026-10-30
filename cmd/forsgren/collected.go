package main

import (
	"errors"
	"fmt"
	"io/fs"
	"slices"
	"strings"

	"github.com/yveshanoulle/forsgren/internal/collect"
)

// The Collected line of the run summary (forsgren#64, step 3c, decision
// #238): a successful run means collection ran correctly, not that all
// requested history was collected, so the summary says which it was, from
// the report collect --cut-report wrote.

// collected is the Collected line, nothing without --collect-report. A report
// that is missing or cannot be read is unknown, never complete.
func (in summaryInput) collected() string {
	if in.collectReport == "" {
		return ""
	}
	report, err := collect.ReadReport(in.collectReport)
	switch {
	case errors.Is(err, fs.ErrNotExist):
		return "- Collected: unknown: collect wrote no report: see the failed collect step\n"
	case err != nil:
		return "- Collected: unknown: collect's report cannot be read: see the collect step\n"
	}
	return "- Collected: " + collectedWords(report) + "\n"
}

// collectedWords are what the line says of report: complete, or incomplete
// with the cut repositories, those whose pull requests alone were cut short
// (forsgren#320, decision #307) and the reset time, then the failed ones.
func collectedWords(report collect.Report) string {
	var parts []string
	if cuts := budgetWords(report); len(cuts) > 0 {
		parts = append(parts, "budget reached; "+strings.Join(cuts, ", ")+"; resets "+report.Reset.UTC().Format(runLayout))
	}
	if len(report.Failed) > 0 {
		failed := make([]string, len(report.Failed))
		for i, f := range report.Failed {
			failed[i] = f.Repository + " failed" + failedWords[f.Kind]
		}
		parts = append(parts, strings.Join(failed, ", "))
	}
	base := "complete"
	if len(parts) > 0 {
		base = "incomplete, " + strings.Join(parts, "; ")
	}
	return strings.Join(slices.Concat([]string{base}, cappedWords(report), serviceWords(report)), "; ")
}

// cappedWords name each repository whose read of the commit files stopped at
// the cap of a run (forsgren#589), with how far the read is, how many commits
// are left and about how many runs they take (forsgren#593). A cap is
// planned, so they never make the run incomplete.
func cappedWords(report collect.Report) []string {
	words := make([]string, len(report.FilesCapped))
	for i, c := range report.FilesCapped {
		words[i] = fmt.Sprintf("%s commit files: %d read this run, %s", c.Repository, collect.CommitFilesPerRun, progressWords(c))
	}
	return words
}

// progressWords say how far c's read is and what is left, the runs left
// rounded up; a report from before forsgren#593 has no counts and keeps the
// words of then.
func progressWords(c collect.CappedFiles) string {
	if !c.Counted() {
		return "the next runs continue"
	}
	runs := (c.Left + collect.CommitFilesPerRun - 1) / collect.CommitFilesPerRun
	return fmt.Sprintf("%d of %d read, %d left (about %s)", c.Read, c.Read+c.Left, c.Left, more(runs, "run"))
}

// serviceWords name each failure issue whose service label found no single
// row of its repository, counted in the total only (forsgren#515, decision
// #517). They never make the run incomplete.
func serviceWords(report collect.Report) []string {
	words := make([]string, len(report.ServiceUnmatched))
	for i, u := range report.ServiceUnmatched {
		what := " is unknown"
		if u.Reason == collect.ServiceAmbiguous {
			what = " is ambiguous (it matches more than one row)"
		}
		words[i] = fmt.Sprintf("failure issue #%d of %s: service %q%s, so the failure was counted in the total only",
			u.Issue, u.Repository, u.Label, what)
	}
	return words
}

// budgetWords describe each repository the budget cut short, then each whose
// pull requests alone it cut short, then each whose backfill of the legacy
// commits it cut short (forsgren#385), then each whose pushes it cut short
// (forsgren#397), then each whose fill of the pull request commits, then of
// the merge push lines, then of the bot status of the stored pull requests, it
// cut short (forsgren#470, forsgren#500), then each whose read of the commit
// files it cut short (forsgren#496).
func budgetWords(report collect.Report) []string {
	var words []string
	fills := slices.Concat(report.PullFillCut, report.PushFillCut, report.PullBotFillCut, report.PushesFillCut)
	for _, c := range report.Cuts {
		words = append(words, cutWords(c))
	}
	for _, cut := range []struct {
		repos []string
		what  string
	}{
		{report.PullsCut, " pull requests cut short (deployments and issues read)"},
		{report.BackfillCut, " legacy commits cut short (deployments, issues and pull requests read)"},
		{report.PushesCut, " pushes cut short (deployments, issues and pull requests read)"},
		{fills, " history fill cut short (the next run continues)"},
		{report.FilesCut, " commit files cut short (the next run continues)"},
	} {
		for _, repo := range cut.repos {
			words = append(words, repo+cut.what)
		}
	}
	return words
}

// failedWords say how a repository failed, by the report's word.
var failedWords = map[string]string{
	collect.FailedPrimary:   " on GitHub's primary rate limit",
	collect.FailedSecondary: " on GitHub's secondary rate limit",
	collect.FailedOther:     " (see the collect step)",
}

// cutWords describe one cut repository: how far it kept, what became of the
// recent read, that its issues and pull requests were not read (forsgren#320,
// decision #327), and whether it is not progressing.
func cutWords(c collect.Cut) string {
	kept := "kept nothing"
	switch {
	case !c.Kept.IsZero():
		kept = "kept up to " + c.Kept.UTC().Format("2006-01-02")
	case c.Recent == collect.RecentKept:
		kept = "kept the newest days"
	}
	parts := []string{kept}
	if c.Recent == collect.RecentDiscarded {
		parts = append(parts, "recent read discarded")
	}
	parts = append(parts, "issues and pull requests not read")
	name := c.Repository + " cut short"
	if c.Progress == collect.ProgressStalled {
		name += " and not progressing"
	}
	return name + " (" + strings.Join(parts, ", ") + ")"
}
