package main

import (
	"github.com/yveshanoulle/forsgren/internal/collect"
	"github.com/yveshanoulle/forsgren/internal/history"
	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// withCommitFiles is data with the files the deployed commits changed
// (data/commit_files.csv beside the history, forsgren#496; none when missing,
// so no commit of a service with paths is read yet). An unknown or malformed
// file fails the render. It also reads what withPushes reads.
func withCommitFiles(data metrics.Data, path string) (metrics.Data, error) {
	files, err := loadOrNone(beside(path, collect.CommitFilesFile), history.LoadCommitFiles)
	if err != nil {
		return metrics.Data{}, err
	}
	data.CommitFiles = files
	return withPushes(data, path)
}
