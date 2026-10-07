package main

import (
	"context"

	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/needs"
)

// setupLabel is the label of forsgren's one setup issue.
const setupLabel = "forsgren-setup"

// setupIssues is the part of the GitHub client that reporting setup needs.
type setupIssues interface {
	FindIssueByMarker(ctx context.Context, repo, label, marker string) (github.SetupIssue, bool, error)
	CreateIssue(ctx context.Context, repo, title, body string, labels []string) (int64, error)
	UpdateIssue(ctx context.Context, repo string, number int64, title, body string) error
	ReopenIssue(ctx context.Context, repo string, number int64, title, body string) error
	CloseIssue(ctx context.Context, repo string, number int64, comment string) error
}

var _ setupIssues = (*github.Client)(nil)

// reportSetup makes the one call the run's missing needs call for on the
// setup issue (forsgren#73): create, update, reopen or close it, or none.
func reportSetup(ctx context.Context, issues setupIssues, repo, version string, missing []needs.Need) error {
	found, ok, err := issues.FindIssueByMarker(ctx, repo, setupLabel, needs.Marker)
	if err != nil {
		return err
	}
	if len(missing) == 0 {
		return closeSetup(ctx, issues, repo, version, found, ok)
	}
	return openSetup(ctx, issues, repo, version, missing, found, ok)
}

// closeSetup closes the setup issue when it is open: nothing is missing, and a
// closed or absent issue needs no write.
func closeSetup(ctx context.Context, issues setupIssues, repo, version string, found github.SetupIssue, ok bool) error {
	if !ok || found.State != "open" {
		return nil
	}
	return issues.CloseIssue(ctx, repo, found.Number, "All items are in place as of forsgren "+version+".")
}

// openSetup creates the setup issue when there is none, updates it when it is
// open and reopens it when it is closed: something is missing.
func openSetup(ctx context.Context, issues setupIssues, repo, version string, missing []needs.Need,
	found github.SetupIssue, ok bool) error {
	title, body := needs.Title(version), needs.Body(version, missing)
	switch {
	case !ok:
		_, err := issues.CreateIssue(ctx, repo, title, body, []string{setupLabel})
		return err
	case found.State == "open":
		return issues.UpdateIssue(ctx, repo, found.Number, title, body)
	default:
		return issues.ReopenIssue(ctx, repo, found.Number, title, body)
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
