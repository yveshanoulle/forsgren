package main

import (
	"context"

	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/update"
)

// metricsWorkflow is the reusable workflow whose pin Dependabot moves.
const metricsWorkflow = "metrics.yml"

// pullLookup reads the open pull requests of one repository.
type pullLookup struct {
	client     *github.Client
	repository string
}

// waiting is the number of the highest open pull request of Dependabot whose
// files move the pin of metrics.yml to version, 0 for none (forsgren#42).
func (l pullLookup) waiting(ctx context.Context, version string) (int64, error) {
	pulls, _, err := l.client.OpenPullRequests(ctx, l.repository)
	if err != nil {
		return 0, err
	}
	var waiting int64
	for _, p := range github.DependabotPulls(pulls) {
		changed, _, err := l.client.PullRequestFiles(ctx, l.repository, p.Number)
		if err != nil {
			return 0, err
		}
		if update.MovesPinTo(updateFiles(changed), metricsWorkflow, version) {
			waiting = max(waiting, p.Number)
		}
	}
	return waiting, nil
}

// updateFiles are the changed files of a pull request as the update package
// reads them.
func updateFiles(changed []github.ChangedFile) []update.File {
	files := make([]update.File, len(changed))
	for i, f := range changed {
		files[i] = update.File{Filename: f.Filename, Patch: f.Patch}
	}
	return files
}
