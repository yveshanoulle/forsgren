package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/page"
)

// errNoRepository: the lookup runs in a workflow, which names the
// installation's repository in GITHUB_REPOSITORY.
var errNoRepository = errors.New("GITHUB_REPOSITORY is not set")

// waitingPullRequest prints the number of the open Dependabot pull request,
// in the installation's own repository (GITHUB_REPOSITORY), that bumps
// forsgren's pin to --version, for render's --waiting-pr (forsgren#40,
// option 1); nothing when there is none. It reads with GITHUB_TOKEN, which
// needs pull-requests: read. A lookup that fails, a 403 for a token without
// that permission included, is not an error: it prints nothing, says why on
// stderr and exits 0, so the page keeps saying the release is available.
func waitingPullRequest(args []string, stdout, stderr io.Writer) int {
	wanted, ok := requiredFlag(stderr, args, "waiting-pull-request", "version", "<x.y.z>",
		"the forsgren release whose Dependabot pull request is looked for")
	if !ok {
		return 2
	}
	if _, isVersion := page.ReleaseVersion(wanted); !isVersion {
		_, _ = fmt.Fprintf(stderr, "waiting-pull-request: --version <x.y.z> is not a version: %q\n", wanted)
		return 2
	}
	number, err := lookUpWaiting(wanted)
	if err != nil {
		_, _ = fmt.Fprintf(stderr, "waiting-pull-request: the waiting pull request is unknown, so the page "+
			"says nothing of it: %v\n", err)
		return 0
	}
	if number != 0 {
		_, _ = fmt.Fprintln(stdout, number)
	}
	return 0
}

// lookUpWaiting is the number of the pull request, or 0 for none.
func lookUpWaiting(version string) (int64, error) {
	repository := strings.TrimSpace(os.Getenv("GITHUB_REPOSITORY"))
	if repository == "" {
		return 0, errNoRepository
	}
	client, err := github.New(githubAPI, strings.TrimSpace(os.Getenv("GITHUB_TOKEN")), github.DefaultMaxPages)
	if err != nil {
		return 0, err
	}
	pulls, _, err := client.OpenPullRequests(context.Background(), repository)
	if err != nil {
		return 0, err
	}
	number, _ := github.ForsgrenBump(pulls, strings.TrimPrefix(version, "v"))
	return number, nil
}
