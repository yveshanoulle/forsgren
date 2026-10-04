package main

import (
	"context"
	"errors"
	"flag"
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
// With --status <path> it also writes how the lookup went, for the run
// summary: ok, no-access (the 403) or failed.
func waitingPullRequest(args []string, stdout, stderr io.Writer) int {
	wanted, statusPath, ok := waitingFlags(args, stderr)
	if !ok {
		return 2
	}
	number, err := lookUpWaiting(wanted)
	if err != nil {
		_, _ = fmt.Fprintf(stderr, "waiting-pull-request: the waiting pull request is unknown, so the page "+
			"says nothing of it: %v\n", err)
	}
	if number != 0 {
		_, _ = fmt.Fprintln(stdout, number)
	}
	writeStatus(statusPath, lookupStatus(err), stderr)
	return 0
}

// waitingFlags parses waiting-pull-request's arguments: the required
// --version, which must be a version, and the optional --status path. It
// returns false once the usage error is on stderr.
func waitingFlags(args []string, stderr io.Writer) (version, statusPath string, ok bool) {
	flags := flag.NewFlagSet("waiting-pull-request", flag.ContinueOnError)
	flags.SetOutput(stderr)
	wanted := flags.String("version", "", "the forsgren release whose Dependabot pull request is looked for, <x.y.z>")
	status := flags.String("status", "", "a file to write how the lookup went to: ok, no-access or failed (optional)")
	if err := flags.Parse(args); err != nil {
		return "", "", false
	}
	if _, isVersion := page.ReleaseVersion(*wanted); !isVersion {
		_, _ = fmt.Fprintf(stderr, "waiting-pull-request: --version <x.y.z> is required and must be a version, got %q\n",
			*wanted)
		return "", "", false
	}
	return *wanted, *status, true
}

// lookupStatus is how a lookup went, from its error.
func lookupStatus(err error) string {
	switch {
	case err == nil:
		return statusOK
	case errors.Is(err, github.ErrPullRequestsDenied):
		return statusNoAccess
	}
	return statusFailed
}

// writeStatus writes status to path, when there is one. A file that cannot
// be written is a note on stderr, never an error: the workflow reads a
// missing status as failed.
func writeStatus(path, status string, stderr io.Writer) {
	if path == "" {
		return
	}
	if err := os.WriteFile(path, []byte(status), 0o600); err != nil {
		_, _ = fmt.Fprintf(stderr, "waiting-pull-request: cannot write the status: %v\n", err)
	}
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
