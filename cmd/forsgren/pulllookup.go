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

// errPullsCut is a list of open pull requests that the client cut at its page
// limit, in which no waiting pull request was found: one on a later page cannot
// be ruled out (forsgren#203).
var errPullsCut = errors.New("the list of open pull requests is cut")

// waiting is the number of the highest open pull request of Dependabot whose
// files move the pin of metrics.yml to version, 0 for none (forsgren#42). A
// match is conclusive even when the list is cut; with no match in a cut list
// it is 0 and errPullsCut, naming the repository and the page limit.
func (l pullLookup) waiting(ctx context.Context, version string) (int64, error) {
	pulls, cut, err := l.client.OpenPullRequests(ctx, l.repository)
	if err != nil {
		return 0, err
	}
	waiting, err := l.highestMoving(ctx, github.DependabotPulls(pulls), version)
	if err != nil {
		return 0, err
	}
	if cut && waiting == 0 {
		return 0, fmt.Errorf("%s: %w at %d page(s), so a waiting pull request cannot be ruled out",
			l.repository, errPullsCut, l.client.MaxPages())
	}
	return waiting, nil
}

// highestMoving is the number of the highest of pulls that moves the pin of
// metrics.yml to version, 0 for none.
func (l pullLookup) highestMoving(ctx context.Context, pulls []github.PullRequest, version string) (int64, error) {
	var highest int64
	for _, p := range pulls {
		moves, err := l.movesPin(ctx, p.Number, version)
		if err != nil {
			return 0, err
		}
		if moves {
			highest = max(highest, p.Number)
		}
	}
	return highest, nil
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
