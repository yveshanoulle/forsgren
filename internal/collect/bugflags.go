package collect

// The bug flags of each repository (forsgren#126): which of its issues carry
// the bug label, as data/issue_bugs.csv (history.IssueBug) holds them next to
// the history.

import (
	"context"
	"path/filepath"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// IssueBugsFile is the name of the bug flags file, kept next to the history.
const IssueBugsFile = "issue_bugs.csv"

// bugsFile is the path of the bug flags file next to o's history.
func (o Options) bugsFile() string { return filepath.Join(filepath.Dir(o.History), IssueBugsFile) }

// bugFlags returns the bug flags of repo's issues to store: every issue GitHub
// lists for the bug label, open or closed, as a bug. What is already stored is
// skipped by history.AppendIssueBugs, so every run adds only what changed.
func (o Options) bugFlags(ctx context.Context, _ held, repo string) ([]history.IssueBug, error) {
	issues, _, err := o.Client.BugIssues(ctx, repo)
	if err != nil {
		return nil, err
	}
	flags := make([]history.IssueBug, 0, len(issues))
	for _, i := range issues {
		flags = append(flags, history.IssueBug{Repository: repo, Issue: i.Number, Bug: true})
	}
	return flags, nil
}
