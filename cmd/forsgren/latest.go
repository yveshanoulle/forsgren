package main

import (
	"context"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/page"
)

// forsgrenRepository is forsgren's own public repository, whose latest
// release the page's footer compares its version with (forsgren#40). Reading
// a public repository's releases leaks nothing.
const forsgrenRepository = "yveshanoulle/forsgren"

// latestRelease prints the version of forsgren's latest release, without its
// leading v, for render's --latest. It reads with GITHUB_TOKEN when the
// environment has one (a workflow's job token lifts the limit of unauthorized
// calls) and without otherwise. A lookup that fails is not an error: it
// prints nothing, says why on stderr and exits 0, so the page is rendered
// without news of a release.
func latestRelease(args []string, stdout, stderr io.Writer) int {
	if len(args) > 0 {
		_, _ = fmt.Fprintln(stderr, "usage: forsgren latest-release")
		return 2
	}
	version, err := lookUpLatest()
	if err != nil {
		_, _ = fmt.Fprintf(stderr, "latest-release: the latest release is unknown, the page says nothing of it: %v\n", err)
		return 0
	}
	_, _ = fmt.Fprintln(stdout, version)
	return 0
}

// lookUpLatest is the version of forsgren's latest release on githubAPI.
func lookUpLatest() (string, error) {
	client, err := github.New(githubAPI, strings.TrimSpace(os.Getenv("GITHUB_TOKEN")), 1)
	if err != nil {
		return "", err
	}
	release, err := client.LatestRelease(context.Background(), forsgrenRepository)
	if err != nil {
		return "", err
	}
	version, ok := page.ReleaseVersion(release.TagName)
	if !ok {
		return "", fmt.Errorf("the tag %q is not a version", release.TagName)
	}
	return version, nil
}
