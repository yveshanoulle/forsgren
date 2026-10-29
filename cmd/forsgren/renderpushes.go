package main

import (
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
// forsgren#583); a missing file of the last four holds none. An
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
	filled, err := history.LoadPushCommitsFilled(beside(path, collect.PushCommitsFilledFile))
	if err != nil {
		return metrics.Data{}, err
	}
	cut, err := history.LoadPushesCut(beside(path, collect.PushesCutFile))
	if err != nil {
		return metrics.Data{}, err
	}
	data.PushesFilled, data.PushesCut = filled, cut
	data.Pushes, data.PushCommits, data.PushesDenied = pushes, commits, denied.Times()
	data.PushesUncollected = absent(beside(path, collect.PushesFile))
	return data, nil
}
