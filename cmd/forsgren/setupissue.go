package main

import (
	"context"

	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/needs"
)

// setupLabel is the label of forsgren's one setup issue.
const setupLabel = "forsgren-setup"

// setupIssues is the part of the GitHub client that reporting the setup needs.
type setupIssues interface {
	FindIssueByMarker(ctx context.Context, repo, label, marker string) (github.SetupIssue, bool, error)
	CreateIssue(ctx context.Context, repo string, text github.IssueText, labels []string) (int64, error)
	UpdateIssue(ctx context.Context, repo string, number int64, text github.IssueText) error
	ReopenIssue(ctx context.Context, repo string, number int64, text github.IssueText) error
	CloseIssue(ctx context.Context, repo string, number int64, comment string) error
}

var _ setupIssues = (*github.Client)(nil)

// setupReport is one run's report on the setup issue: the client it writes
// with, the installation's repository the issue lives in and the running
// forsgren version.
type setupReport struct {
	issues  setupIssues
	repo    string
	version string
}

// foundIssue is what one lookup of the setup issue found: the issue, and
// whether there is one at all (ok). A lookup that failed is an error instead,
// never a foundIssue: not found and failed stay distinct.
type foundIssue struct {
	issue github.SetupIssue
	ok    bool
}

// find looks the setup issue up, the one lookup of a run.
func (s setupReport) find(ctx context.Context) (foundIssue, error) {
	issue, ok, err := s.issues.FindIssueByMarker(ctx, s.repo, setupLabel, needs.Marker)
	return foundIssue{issue: issue, ok: ok}, err
}

// report makes the one call the run's missing needs call for on the setup
// issue (forsgren#73), given what find found: create, update, reopen or
// close it, or none.
func (s setupReport) report(ctx context.Context, found foundIssue, items setupItems) error {
	if items.empty() {
		return s.closeIssue(ctx, found.issue, found.ok)
	}
	return s.openIssue(ctx, items, found.issue, found.ok)
}

// closeIssue closes the setup issue when it is open: nothing is missing, and
// a closed or absent issue needs no write.
func (s setupReport) closeIssue(ctx context.Context, found github.SetupIssue, ok bool) error {
	if !ok || found.State != "open" {
		return nil
	}
	return s.issues.CloseIssue(ctx, s.repo, found.Number, "All items are in place as of forsgren "+s.version+".")
}

// openIssue creates the setup issue when there is none, updates it when it
// is open and reopens it when it is closed: something is missing.
func (s setupReport) openIssue(ctx context.Context, items setupItems, found github.SetupIssue, ok bool) error {
	text := github.IssueText{Title: needs.Title(s.version), Body: needs.Body(s.version, items.missing, items.refused)}
	switch {
	case !ok:
		_, err := s.issues.CreateIssue(ctx, s.repo, text, []string{setupLabel})
		return err
	case found.State == "open":
		return s.issues.UpdateIssue(ctx, s.repo, found.Number, text)
	default:
		return s.issues.ReopenIssue(ctx, s.repo, found.Number, text)
	}
}

// setupStatus is how the write of the setup issue went, from its error
// (forsgren#73): a failed write never turns the run red, it is reported as
// a status. A refused 403 (no issues: write) is no-access; the rest is the
// pull request lookup's mapping.
func setupStatus(err error) string {
	if github.IsRefused(err) {
		return statusNoAccess
	}
	return lookupStatus(err)
}

// setupItems are what one run puts on the setup issue (forsgren#538): the
// missing requirements and the refused settings, under their own headings.
type setupItems struct {
	missing []needs.Need
	refused []needs.Refusal
}

// empty says whether there is nothing to report: the issue is then closed.
func (i setupItems) empty() bool { return len(i.missing) == 0 && len(i.refused) == 0 }

// count is the number of items.
func (i setupItems) count() int { return len(i.missing) + len(i.refused) }
