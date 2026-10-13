package collect

// The bug flags of each repository (forsgren#126): which of its issues carry
// the bug label, as data/issue_bugs.csv (history.IssueBug) holds them next to
// the history.

import (
	"context"
	"errors"
	"io/fs"
	"path/filepath"
	"strings"

	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// IssueBugsFile is the name of the bug flags file, kept next to the history.
const IssueBugsFile = "issue_bugs.csv"

// bugsFile is the path of the bug flags file next to o's history.
func (o Options) bugsFile() string { return filepath.Join(filepath.Dir(o.History), IssueBugsFile) }

// bugFlags returns the bug flags of repo's issues to store: every issue GitHub
// lists for the bug label, open or closed, as a bug, and every issue stored as
// a bug that it no longer lists, as not a bug, unless its read stopped at the
// page cap, when an issue it did not list may still carry the label and the
// stored flags are kept, with a warning on stderr. What is already stored is
// skipped by history.AppendIssueBugs, so every run adds only what changed.
func (o Options) bugFlags(ctx context.Context, _ held, repo string) ([]history.IssueBug, error) {
	issues, stored, cut, err := o.readBugs(ctx, repo)
	if err != nil {
		return nil, err
	}
	listed := make(map[int64]bool, len(issues))
	flags := make([]history.IssueBug, 0, len(issues))
	for _, i := range issues {
		listed[i.Number] = true
		flags = append(flags, history.IssueBug{Repository: repo, Issue: i.Number, Bug: true})
	}
	if cut {
		o.warn("collect: %s: the bug read stopped at %d page(s) of issues; "+
			"the stored bug flags are kept\n", repo, github.FullReadMaxPages)
		return flags, nil
	}
	return append(flags, lostLabel(stored, repo, listed)...), nil
}

// lostLabel is the issues of repo that stored says are bugs and listed, the
// numbers GitHub lists under the bug label, does not hold: each as not a bug.
func lostLabel(stored []history.IssueBug, repo string, listed map[int64]bool) []history.IssueBug {
	var lost []history.IssueBug
	for _, b := range stored {
		if b.Bug && strings.EqualFold(b.Repository, repo) && !listed[b.Issue] {
			lost = append(lost, history.IssueBug{Repository: repo, Issue: b.Issue})
		}
	}
	return lost
}

// readBugs is the issues GitHub lists for repo under the bug label, the bug
// flags stored so far, as their newest lines say, and whether the list stopped
// at the page cap; a missing file holds none, one that cannot be read refuses
// the repository before GitHub is asked.
func (o Options) readBugs(ctx context.Context, repo string) ([]github.RepoIssue, []history.IssueBug, bool, error) {
	stored, err := history.LoadIssueBugs(o.bugsFile())
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return nil, nil, false, err
	}
	issues, cut, err := o.Client.BugIssues(ctx, repo)
	return issues, stored, cut, err
}
