package main

import (
	"context"
	"fmt"
	"io"
	"os"
	"time"

	"github.com/yveshanoulle/forsgren/internal/page"
)

// forsgrenRepository is forsgren's own public repository, whose latest
// release the page's footer compares its version with (forsgren#40). Reading
// a public repository's releases leaks nothing.
const forsgrenRepository = "yveshanoulle/forsgren"

// latestRelease prints the version of forsgren's latest release, without its
// leading v, for render's --latest, and with --published writes the time the
// release was published to a file, for run-summary's cooldown (forsgren#194). It reads with GITHUB_TOKEN when the
// environment has one (a workflow's job token lifts the limit of unauthorized
// calls) and without otherwise. A lookup that fails is not an error: it
// prints nothing, says why on stderr and exits 0, so the page is rendered
// without news of a release.
func latestRelease(args []string, stdout, stderr io.Writer) int {
	flags := newFlags("latest-release", stderr)
	var published string
	flags.StringVar(&published, "published", "",
		"write the time the release was published, RFC 3339 in UTC, to this file (optional)")
	if err := flags.Parse(args); err != nil {
		return 2
	}
	if flags.NArg() > 0 {
		_, _ = fmt.Fprintln(stderr, "usage: forsgren latest-release [--published <path>]")
		return 2
	}
	version, publishedAt, err := lookUpLatest()
	if err != nil {
		_, _ = fmt.Fprintf(stderr, "latest-release: the latest release is unknown, the page says nothing of it: %v\n", err)
		return 0
	}
	_, _ = fmt.Fprintln(stdout, version)
	if err := writePublished(published, publishedAt); err != nil {
		_, _ = fmt.Fprintf(stderr, "latest-release: cannot write the publish time, the summary says nothing "+
			"of the cooldown: %v\n", err)
	}
	return 0
}

// writePublished writes the time a release was published to path, one UTC RFC
// 3339 line, for run-summary's cooldown (forsgren#194). No path, or a release
// without a time, is nothing to do.
func writePublished(path string, at time.Time) error {
	if path == "" || at.IsZero() {
		return nil
	}
	return os.WriteFile(path, []byte(at.UTC().Format(time.RFC3339)+"\n"), 0o600)
}

// lookUpLatest is the version of forsgren's latest release on githubAPI and
// the time it was published, zero when GitHub names none.
func lookUpLatest() (string, time.Time, error) {
	client, err := jobClient(1)
	if err != nil {
		return "", time.Time{}, err
	}
	release, err := client.LatestRelease(context.Background(), forsgrenRepository)
	if err != nil {
		return "", time.Time{}, err
	}
	version, ok := page.ReleaseVersion(release.TagName)
	if !ok {
		return "", time.Time{}, fmt.Errorf("the tag %q is not a version", release.TagName)
	}
	return version, release.PublishedAt, nil
}
