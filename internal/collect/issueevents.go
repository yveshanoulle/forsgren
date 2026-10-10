package collect

// The issue events of each repository (forsgren#76, step 4): every issue of
// a configured repository, whatever its labels, turned into the events
// data/issues.csv holds (history.IssueEvent), next to the history
// (IssuesFile).

import (
	"context"
	"path/filepath"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// IssuesFile is the name of the issue events file, kept next to the history:
// data/issues.csv beside data/deployments.csv.
const IssuesFile = "issues.csv"

// issuesFile is the path of the issue events file next to o's history.
func (o Options) issuesFile() string { return filepath.Join(filepath.Dir(o.History), IssuesFile) }

// issueEvents reads repo's issues and returns the events to store.
func (o Options) issueEvents(_ context.Context, _ string) ([]history.IssueEvent, error) {
	return nil, nil
}
