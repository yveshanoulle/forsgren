package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/update"
)

// errFilesCut is a pull request with more files than the client reads: the
// files not read could be anything, so the guard is not asked.
var errFilesCut = errors.New("the pull request has more files than were read, so the guard cannot judge it")

// checkUpdate is the subcommand the update workflow runs on Dependabot's pull
// request in an installation's data repository: it reads the pull request and
// the release of the version it moves the pin to (none is looked up when the
// diff moves no pin), asks the guard, and says `merge <old> to <new>` or `left
// for a human: <reason>`. Exit 0 is merge, 1 left for a human, 2 a usage,
// config or network error. An installation whose config has auto_update off
// is left for a human without a request to GitHub. It reads with
// GITHUB_TOKEN, which needs pull-requests: read.
func checkUpdate(args []string, stdout, stderr io.Writer) int {
	in, ok := updateInput(args, stderr)
	if !ok {
		return 2
	}
	if !in.config.AutoUpdate {
		_, _ = fmt.Fprintln(stdout, "left for a human: auto_update is off")
		return 1
	}
	decision, err := decideUpdate(context.Background(), in)
	if err != nil {
		_, _ = fmt.Fprintf(stderr, "check-update: %v\n", err)
		return 2
	}
	if !decision.Merge {
		_, _ = fmt.Fprintf(stdout, "left for a human: %s\n", decision.Reason)
		return 1
	}
	_, _ = fmt.Fprintf(stdout, "merge %s to %s\n", decision.Old, decision.New)
	return 0
}

// pullToCheck is what check-update is asked about: the installation's config
// and one pull request of its data repository.
type pullToCheck struct {
	config config.Config
	dir    string
	repo   string
	number int64
}

// updateInput parses check-update's three required flags and loads the
// config. It returns false once the error is on stderr.
func updateInput(args []string, stderr io.Writer) (pullToCheck, bool) {
	values, ok := requiredFlags(stderr, args, "check-update",
		flagSpec{"config", "<path>", "the forsgren.config.yml of the installation"},
		flagSpec{"repo", "<owner/name>", "the data repository"},
		flagSpec{"pull", "<number>", "Dependabot's pull request in it"})
	if !ok {
		return pullToCheck{}, false
	}
	number, err := pullNumber(values[2])
	if err != nil {
		_, _ = fmt.Fprintf(stderr, "check-update: %v\n", err)
		return pullToCheck{}, false
	}
	if !github.IsRepositoryName(values[1]) {
		_, _ = fmt.Fprintf(stderr, "check-update: --repo <owner/name> must be one owner/name, got %q\n", values[1])
		return pullToCheck{}, false
	}
	cfg, err := config.Load(values[0])
	if err != nil {
		_, _ = fmt.Fprintf(stderr, "check-update: %v\n", err)
		return pullToCheck{}, false
	}
	return pullToCheck{config: cfg, dir: filepath.Dir(values[0]), repo: values[1], number: number}, true
}

// pullNumber is the number of a pull request as --pull writes it: a whole
// number of 1 or more.
func pullNumber(s string) (int64, error) {
	number, err := strconv.ParseInt(s, 10, 64)
	if err != nil || number < 1 {
		return 0, fmt.Errorf("--pull <number> must be a whole number of 1 or more, got %q", s)
	}
	return number, nil
}

// decideUpdate reads the pull request and the release of its new version
// from githubAPI and asks the guard.
func decideUpdate(ctx context.Context, in pullToCheck) (update.Decision, error) {
	client, err := jobClient(github.DefaultMaxPages)
	if err != nil {
		return update.Decision{Merge: true}, nil
	}
	author, files, err := readPull(ctx, client, in)
	if err != nil {
		return update.Decision{}, err
	}
	var release update.Release
	if version, found := update.NewVersion(files); found {
		if release, err = lookUpTag(ctx, client, version); err != nil {
			return update.Decision{}, err
		}
	}
	pull := update.Pull{
		Author: author, Files: files, Release: release, Level: in.config.AutoUpdateLevel,
		Present: presentCallers(in.dir),
	}
	return update.Decide(pull), nil
}

// presentCallers are the caller files that exist under dir, the checkout of
// the pull request's base commit, as repository paths. A file that cannot be
// statted counts as absent.
func presentCallers(dir string) []string {
	var present []string
	for _, path := range update.Callers() {
		if _, err := os.Stat(filepath.Join(dir, path)); err == nil {
			present = append(present, path)
		}
	}
	return present
}

// readPull is the author and the changed files of the pull request, every
// file of it: errFilesCut when the client stopped before the last page.
func readPull(ctx context.Context, client *github.Client, in pullToCheck) (string, []update.File, error) {
	author, err := client.PullRequestAuthor(ctx, in.repo, in.number)
	if err != nil {
		return "", nil, err
	}
	changed, truncated, err := client.PullRequestFiles(ctx, in.repo, in.number)
	if err != nil {
		return "", nil, err
	}
	if truncated {
		return "", nil, errFilesCut
	}
	files := make([]update.File, len(changed))
	for i, f := range changed {
		files[i] = update.File{Filename: f.Filename, Patch: f.Patch}
	}
	return author, files, nil
}

// lookUpTag is forsgren's release of tag: whether it is published and, only
// then, the commit the tag points at; a release that is not published has no
// tag worth asking for.
func lookUpTag(ctx context.Context, client *github.Client, tag string) (update.Release, error) {
	published, err := client.PublishedRelease(ctx, forsgrenRepository, tag)
	if err != nil || !published {
		return update.Release{}, err
	}
	sha, err := client.TagCommit(ctx, forsgrenRepository, tag)
	if err != nil {
		return update.Release{}, err
	}
	return update.Release{Published: true, SHA: sha}, nil
}
