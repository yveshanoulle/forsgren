package collect

// The failure issues taken back (forsgren#155): data/failures_withdrawn.csv,
// next to the history. failures.csv only grows, so an issue that loses its
// failure label cannot leave it; a new line in this file says it no longer
// counts, and change fail rate leaves it out.
//
// A run learns it from the daily read of every issue (dailyRead), which
// GitHub's since filter extends to an issue whose labels changed, since that
// updates it: a stored failure issue listed without the failure label is
// withdrawn, for the reason label_removed; one closed as not planned
// (state_reason) is withdrawn for the reason not_planned. A withdrawn issue
// listed again as a failure is reinstated by a line with withdrawn false. No
// request is added.

import (
	"context"
	"errors"
	"io/fs"
	"path/filepath"
	"slices"
	"strings"
	"time"

	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// WithdrawnFile is the name of the withdrawn failures file, kept next to the
// history: data/failures_withdrawn.csv beside data/failures.csv.
const WithdrawnFile = "failures_withdrawn.csv"

// failureLabel is the label that makes an issue a failure (forsgren#6).
const failureLabel = "failure"

// withdrawnFile is the path of the withdrawn failures file next to o's history.
func (o Options) withdrawnFile() string { return filepath.Join(filepath.Dir(o.History), WithdrawnFile) }

// loadWithdrawn reads the withdrawn file at path: the issues that their newest
// line withdraws. A missing file holds none; one that cannot be read refuses
// the run. It also says whether the file was there.
func loadWithdrawn(path string) (map[history.IssueKey]bool, bool, error) {
	stored, err := history.LoadWithdrawals(path)
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return nil, false, err
	}
	out := map[history.IssueKey]bool{}
	for _, w := range stored {
		out[w.Key()] = w.Withdrawn
	}
	return out, err == nil, nil
}

// withdrawals returns the withdrawals to store from repo's issues of the daily
// read: each issue stored as a failure that withdrawalReason says is taken
// back, and each that is withdrawn but counts again, as a reinstatement (no
// reason). What is already stored is skipped by history.AppendWithdrawals.
func (o Options) withdrawals(h held, repo string, issues []github.RepoIssue) []history.Withdrawal {
	var out []history.Withdrawal
	for _, i := range issues {
		key := history.IssueKeyOf(repo, i.Number)
		if _, stored := h.failures[key]; !stored {
			continue
		}
		reason := withdrawalReason(i)
		if reason != "" || h.withdrawn[key] {
			out = append(out, history.Withdrawal{Repository: repo, Issue: i.Number, Withdrawn: reason != "",
				Reason: reason, At: wholeSecond(o.Now)})
		}
	}
	return out
}

// withdrawalReason is why the stored failure i no longer counts: it is listed
// without the failure label (the label is the ruling, forsgren#6), or it is
// closed as not planned; "" when it still counts. A lost label comes first.
func withdrawalReason(i github.RepoIssue) string {
	switch {
	case !hasLabel(i, failureLabel):
		return history.ReasonLabelRemoved
	case i.State == "closed" && i.StateReason == history.ReasonNotPlanned:
		return history.ReasonNotPlanned
	}
	return ""
}

// hasLabel says whether i carries label, GitHub's names compared ignoring case.
func hasLabel(i github.RepoIssue, label string) bool {
	return slices.ContainsFunc(i.Labels, func(l string) bool { return strings.EqualFold(l, label) })
}

// catchUp is the one-time catch-up of an installation from before
// forsgren#155, whose stored failures may have lost their label long ago: a
// run that finds no failures_withdrawn.csv re-reads each stored failure that
// can still count (withdrawalsOf), one GET per issue (one GitHub says is gone is
// withdrawn as issue_gone), and holds what it finds here instead of storing it
// per repository. finishCatchUp writes it, and so creates the file, only when
// every repository succeeded; a run that failed anywhere, a rate limit
// included, writes nothing, so the next one does the catch-up again.
type catchUp struct{ found []history.Withdrawal }

// hold takes *w from a repository's batch into the catch-up, leaving the
// batch none; it does nothing when there is no catch-up (c nil).
func (c *catchUp) hold(w *[]history.Withdrawal) {
	if c != nil {
		c.found = append(c.found, *w...)
		*w = nil
	}
}

// finishCatchUp writes the catch-up's withdrawals, creating the file even when
// there are none so it is not done again, unless a repository failed.
func (o Options) finishCatchUp(h held, failed int) error {
	if h.late == nil || failed > 0 {
		return nil
	}
	_, err := history.AppendWithdrawals(o.withdrawnFile(), h.late.found)
	return err
}

// countingWindow is how far back an issue was opened to be counted by change
// fail rate, the window of the metrics.
const countingWindow = 30 * 24 * time.Hour

// withdrawalsOf is repo's withdrawals: those of the daily read, and in a
// catch-up run (h.late) also those of the stored failures that can still count
// and the daily read did not list, each read with IssueByNumber: for N such
// failures, N requests, once per installation. An issue GitHub says is gone
// (410, or 404 once the repository's own issue list was read in this run) is
// withdrawn as issue_gone; any other error, 403 and rate limit included, fails
// the repository.
func (o Options) withdrawalsOf(ctx context.Context, h held, repo string, daily []github.RepoIssue,
) ([]history.Withdrawal, error) {
	if h.late == nil {
		return o.withdrawals(h, repo, daily), nil
	}
	issues := slices.Clone(daily)
	var gone []history.Withdrawal
	for _, n := range o.countingFailures(h, repo, daily) {
		i, err := o.Client.IssueByNumber(ctx, repo, n)
		switch {
		case errors.Is(err, github.ErrIssueGone):
			gone = append(gone, history.Withdrawal{Repository: repo, Issue: n, Withdrawn: true,
				Reason: history.ReasonIssueGone, At: wholeSecond(o.Now)})
		case err != nil:
			return nil, err
		default:
			issues = append(issues, i)
		}
	}
	return append(o.withdrawals(h, repo, issues), gone...), nil
}

// needsReread says whether the stored failure f is repo's, can still count and
// is not among the numbers listed.
func (o Options) needsReread(f history.Failure, repo string, listed map[int64]bool) bool {
	if !strings.EqualFold(f.Repository, repo) {
		return false
	}
	return o.canStillCount(f) && !listed[f.Issue]
}

// canStillCount says whether the stored failure f is open or was opened in the
// last 30 days, the window of change fail rate.
func (o Options) canStillCount(f history.Failure) bool {
	return f.ClosedAt.IsZero() || !f.OpenedAt.Before(o.Now.Add(-countingWindow))
}

// countingFailures is the numbers of repo's stored failures that are open or
// were opened in the last 30 days and that daily does not list, oldest first.
func (o Options) countingFailures(h held, repo string, daily []github.RepoIssue) []int64 {
	listed := map[int64]bool{}
	for _, i := range daily {
		listed[i.Number] = true
	}
	var out []int64
	for _, f := range h.failures {
		if o.needsReread(f, repo, listed) {
			out = append(out, f.Issue)
		}
	}
	slices.Sort(out)
	return out
}
