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
	return nil
}
