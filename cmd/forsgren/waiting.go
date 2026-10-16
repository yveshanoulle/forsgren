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
// With --status <path> it also writes how the lookup went, for the run
// summary: ok, no-access (the 403), rate-limited (GitHub's rate limit),
// truncated (the list of open pull requests was cut at the page limit with no
// waiting pull request in it, forsgren#203) or failed.
func waitingPullRequest(args []string, stdout, stderr io.Writer) int {
	wanted, statusPath, ok := waitingFlags(args, stderr)
	if !ok {
		return 2
	}
	number, err := lookUpWaiting(wanted, stderr)
	if err != nil {
		_, _ = fmt.Fprintln(stderr, lookupNote(err))
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
	flags := newFlags("waiting-pull-request", stderr)
	wanted := flags.String("version", "", "the forsgren release whose Dependabot pull request is looked for, <x.y.z>")
	status := flags.String("status", "",
		"a file to write how the lookup went to: ok, no-access, rate-limited, truncated or failed (optional)")
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

// lookupNote is the line on stderr for a lookup that ended in err: for a cut
// list that the lookup cannot say there is no waiting pull request, else that
// the waiting pull request is unknown, so the page says nothing of it.
func lookupNote(err error) string {
	if errors.Is(err, errPullsCut) {
		return "waiting-pull-request: " + err.Error()
	}
	return "waiting-pull-request: the waiting pull request is unknown, so the page says nothing of it: " + err.Error()
}

// lookupStatus is how a lookup went, from its error.
func lookupStatus(err error) string {
	switch {
	case err == nil:
		return statusOK
	case errors.Is(err, github.ErrPullRequestsDenied):
		return statusNoAccess
	case errors.Is(err, github.ErrRateLimit):
		return statusRateLimited
	case errors.Is(err, errPullsCut):
		return statusTruncated
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

// lookUpWaiting is the number of the pull request, or 0 for none: of the open
// pull requests of Dependabot, the highest whose changed files move the pin of
// metrics.yml to version, so a pull request is found by what it changes, not by
// the name of its branch (forsgren#42).
func lookUpWaiting(version string, stderr io.Writer) (int64, error) {
	repository := strings.TrimSpace(os.Getenv("GITHUB_REPOSITORY"))
	if repository == "" {
		return 0, errNoRepository
	}
	client, err := jobClient(github.DefaultMaxPages)
	if err != nil {
		return 0, err
	}
	return pullLookup{client, repository, stderr}.waiting(context.Background(), strings.TrimPrefix(version, "v"))
}
