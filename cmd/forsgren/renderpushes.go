package main

import (
	"errors"

	"github.com/yveshanoulle/forsgren/internal/collect"
	"github.com/yveshanoulle/forsgren/internal/history"
	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// withPushes is data with what the push measures read beside the history at
// path (forsgren#397, step 4): the pushes to main (data/pushes.csv; when it is
// missing PushesUncollected says so), the commits they brought
// (data/push_commits.csv) and the repositories whose push read GitHub refused
// (data/pushes_denied.csv) and the repositories whose fill of the merge
// pushes' lines is done (data/push_commits_filled.csv, forsgren#470) and the
// repositories whose push read stopped at the page cap (data/pushes_cut.csv,
// forsgren#583) and those whose activity list GitHub keeps only back to a
// push (data/pushes_github_end.csv, forsgren#583 step 3); a missing file of
// the last five holds none. An
// unknown or malformed file of any fails the render.
func withPushes(data metrics.Data, path string) (metrics.Data, error) {
	pushes, err := loadOrNone(beside(path, collect.PushesFile), history.LoadPushes)
	if err != nil {
		return metrics.Data{}, err
	}
	commits, err := loadOrNone(beside(path, collect.PushCommitsFile), history.LoadPushCommits)
	if err != nil {
		return metrics.Data{}, err
	}
	denied, err := history.LoadPushesDenied(beside(path, collect.PushesDeniedFile))
	if err != nil {
		return metrics.Data{}, err
	}
	data.Pushes, data.PushCommits, data.PushesDenied = pushes, commits, denied.Times()
	data.PushesUncollected = absent(beside(path, collect.PushesFile))
	return withPushMarks(data, path)
}

// withPushMarks is data with the push marks beside the history at path: the
// merge push fill (data/push_commits_filled.csv), the cut reads
// (data/pushes_cut.csv) and GitHub's ends (data/pushes_github_end.csv).
func withPushMarks(data metrics.Data, path string) (metrics.Data, error) {
	var errs [3]error
	data.PushesFilled, errs[0] = history.LoadPushCommitsFilled(beside(path, collect.PushCommitsFilledFile))
	data.PushesCut, errs[1] = history.LoadPushesCut(beside(path, collect.PushesCutFile))
	data.PushesGitHubEnd, errs[2] = history.LoadPushesGitHubEnd(beside(path, collect.PushesGitHubEndFile))
	if err := errors.Join(errs[:]...); err != nil {
		return metrics.Data{}, err
	}
	return data, nil
}
