package main

import (
	"errors"
	"io/fs"
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
// with the cut repositories and the reset time, then the failed ones.
func collectedWords(report collect.Report) string {
	var parts []string
	if len(report.Cuts) > 0 {
		cuts := make([]string, len(report.Cuts))
		for i, c := range report.Cuts {
			cuts[i] = cutWords(c)
		}
		parts = append(parts, "budget reached; "+strings.Join(cuts, ", ")+"; resets "+report.Reset.UTC().Format(runLayout))
	}
	if len(report.Failed) > 0 {
		failed := make([]string, len(report.Failed))
		for i, f := range report.Failed {
			failed[i] = f.Repository + " failed" + failedWords[f.Kind]
		}
		parts = append(parts, strings.Join(failed, ", "))
	}
	if len(parts) == 0 {
		return "complete"
	}
	return "incomplete, " + strings.Join(parts, "; ")
}

// failedWords say how a repository failed, by the report's word.
var failedWords = map[string]string{
	collect.FailedPrimary:   " on GitHub's primary rate limit",
	collect.FailedSecondary: " on GitHub's secondary rate limit",
	collect.FailedOther:     " (see the collect step)",
}

// cutWords describe one cut repository: how far it kept, what became of the
// recent read, that its issues were not read, and whether it is not
// progressing.
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
	parts = append(parts, "issues not read")
	name := c.Repository + " cut short"
	if c.Progress == collect.ProgressStalled {
		name += " and not progressing"
	}
	return name + " (" + strings.Join(parts, ", ") + ")"
}
