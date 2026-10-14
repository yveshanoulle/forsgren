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
// (state_reason) is withdrawn for the reason not_planned. No request is added.

import (
	"path/filepath"
	"slices"
	"strings"

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

// withdrawals returns the withdrawals to store from repo's issues of the daily
// read: each issue stored as a failure that withdrawalReason says is taken
// back. What is already stored is skipped by history.AppendWithdrawals.
func (o Options) withdrawals(h held, repo string, issues []github.RepoIssue) []history.Withdrawal {
	var out []history.Withdrawal
	for _, i := range issues {
		if _, stored := h.failures[history.IssueKeyOf(repo, i.Number)]; !stored {
			continue
		}
		if reason := withdrawalReason(i); reason != "" {
			out = append(out, history.Withdrawal{Repository: repo, Issue: i.Number, Withdrawn: true,
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
