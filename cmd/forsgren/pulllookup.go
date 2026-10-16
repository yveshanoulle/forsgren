package main

import (
	"context"
	"errors"
	"fmt"
	"io"

	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/update"
)

// metricsWorkflow is the reusable workflow whose pin Dependabot moves.
const metricsWorkflow = "metrics.yml"

// pullLookup reads the open pull requests of one repository.
type pullLookup struct {
	client     *github.Client
	repository string
	stderr     io.Writer
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
		moves, err := l.movesPin(ctx, p.Number, version)
		if err != nil {
			return 0, err
		}
		if moves {
			waiting = max(waiting, p.Number)
		}
	}
	return waiting, nil
}

// movesPin says whether pull request number moves the pin of metrics.yml to
// version. A pull request with more files than were read is no match, noted
// on stderr: the files not read could change anything.
func (l pullLookup) movesPin(ctx context.Context, number int64, version string) (bool, error) {
	files, err := pullFiles(ctx, l.client, l.repository, number)
	if errors.Is(err, errFilesCut) {
		_, _ = fmt.Fprintf(l.stderr, "waiting-pull-request: pull request #%d has more files than were read, "+
			"so it is not looked at\n", number)
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return update.MovesPinTo(files, metricsWorkflow, version), nil
}

// pullFiles are the changed files of pull request number of repo as the
// update package reads them, every file of it: errFilesCut when the client
// stopped before the last page. check-update and the waiting pull request
// read a pull request's files through it.
func pullFiles(ctx context.Context, client *github.Client, repo string, number int64) ([]update.File, error) {
	changed, cut, err := client.PullRequestFiles(ctx, repo, number)
	if err != nil {
		return nil, err
	}
	if cut {
		return nil, errFilesCut
	}
	files := make([]update.File, len(changed))
	for i, f := range changed {
		files[i] = update.File{Filename: f.Filename, Patch: f.Patch}
	}
	return files, nil
}
