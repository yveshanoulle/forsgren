package collect

// How a run fills the Report (report.go) while it collects (forsgren#64,
// step 3b): the cut runs mark, and the cuts and failures of the repositories.

import (
	"errors"
	"strings"
	"time"

	"github.com/yveshanoulle/forsgren/internal/github"
)

// cutOf is what a cut left of repo: the Cut for the report, and the cut runs
// mark brought up to date. A repository progressed when its read mark moved
// or it kept a record; one that did not is noted in cut_runs.csv the first
// time (progress no), and is stalled when it already is.
func (h held) cutOf(repo string, w whole, now time.Time) Cut {
	c := Cut{Repository: repo, Kept: w.reach, Recent: w.recent, Progress: ProgressYes}
	key := strings.ToLower(repo)
	if !w.reach.IsZero() || len(w.records) > 0 {
		delete(h.cutRuns, key)
		return c
	}
	if _, was := h.cutRuns[key]; was {
		c.Progress = ProgressStalled
		return c
	}
	h.cutRuns[key] = wholeSecond(now)
	c.Progress = ProgressNo
	return c
}

// noteCutDone takes repo's cut runs mark away: it was read to the end.
func (h held) noteCutDone(repo string) { delete(h.cutRuns, strings.ToLower(repo)) }

// reportCut adds the Cut that err (a budget cut) carries to the report, or
// the repository whose backfill of the legacy commits it cut short.
func (o Options) reportCut(err error) {
	var c *cutReport
	var b *backfillCut
	switch {
	case o.Report == nil:
	case errors.As(err, &c):
		o.Report.Cuts = append(o.Report.Cuts, c.Cut)
	case errors.As(err, &b):
		o.Report.BackfillCut = append(o.Report.BackfillCut, b.repo)
	}
}

// reportPullsCut adds repo, whose pull requests alone the budget cut short,
// to the report (decision #307).
func (o Options) reportPullsCut(repo string) {
	if o.Report != nil {
		o.Report.PullsCut = append(o.Report.PullsCut, repo)
	}
}

// reportPushesCut adds repo, whose pushes alone the budget cut short, to the
// report (forsgren#397).
func (o Options) reportPushesCut(repo string) {
	if o.Report != nil {
		o.Report.PushesCut = append(o.Report.PushesCut, repo)
	}
}

// reportFailed adds repo, failed with err, to the report, by which rate limit
// it was.
func (o Options) reportFailed(repo string, err error) {
	if o.Report == nil {
		return
	}
	kind := FailedOther
	switch {
	case errors.Is(err, github.ErrPrimaryLimit):
		kind = FailedPrimary
	case errors.Is(err, github.ErrSecondaryLimit):
		kind = FailedSecondary
	}
	o.Report.Failed = append(o.Report.Failed, Failed{repo, kind})
}

// closeReport ends the report: the time the budget resets, when a repository
// or its pull requests were cut short.
func (o Options) closeReport() {
	if o.Report == nil || !o.Report.incomplete() {
		return
	}
	if reset, ok := o.Client.BudgetReset(); ok {
		o.Report.Reset = reset.UTC()
	}
}
