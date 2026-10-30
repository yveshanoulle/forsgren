package metrics

// The Commits of a service's or a rule's row on the Data page (forsgren#589,
// Yves's rulings): with paths, the oldest author date over the row's own
// deployed commits that touch its paths and the pushed commits of its
// repository that touch them (both through pathScope, so a commit whose files
// are not read yet counts for none); marked Cut, earlier data not yet read,
// while a repository of the row has no line in data/push_files_filled.csv,
// collect reading the files of its pushed commits newest first. Without
// paths no commit can be told to be the row's own: Per repository.

import (
	"slices"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// serviceCommits is the Commits of a row over its own data and the
// repositories in, counting the commits scope holds; Per repository for the
// nil scope of a row without paths.
func (s startsSource) serviceCommits(own Data, in map[string]bool, scope *pathScope) DataStart {
	if scope == nil {
		return DataStart{PerRepository: true}
	}
	deployed := earliest(slices.DeleteFunc(slices.Clone(own.Commits), func(c history.Commit) bool {
		return !scope.touches(c)
	}), in, func(c history.Commit) (string, time.Time) { return c.Repository, c.AuthoredAt })
	pushed := earliest(slices.DeleteFunc(slices.Clone(s.data.PushCommits), func(c history.PushCommit) bool {
		return !scope.touches(history.Commit{Repository: c.Repository, SHA: c.SHA})
	}), in, func(c history.PushCommit) (string, time.Time) { return c.Repository, c.AuthoredAt })
	commits := earliestOf(deployed, pushed)
	commits.Cut = commits.Stored() && !allHeld(s.data.PushFilesFilled, in)
	return commits
}

// allHeld says whether marks holds every repository of in, ignoring case.
func allHeld(marks history.Reach, in map[string]bool) bool {
	for repository := range in {
		if !marks.Holds(repository) {
			return false
		}
	}
	return true
}
