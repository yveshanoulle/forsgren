package main

import (
	"fmt"
	"io"
	"slices"
	"strconv"
	"strings"

	"github.com/yveshanoulle/forsgren/internal/page"
)

// The ways the lookup of the waiting pull request went, as waiting-pull-
// request writes them to --status and run-summary reads them from
// --pr-check; rate-limited is GitHub's rate limit, never a missing
// permission; skipped is a run with no latest release to look one up for.
const (
	statusOK          = "ok"
	statusNoAccess    = "no-access"
	statusRateLimited = "rate-limited"
	statusFailed      = "failed"
	statusSkipped     = "skipped"
)

// statuses are the values of --pr-check.
var statuses = []string{statusOK, statusNoAccess, statusRateLimited, statusFailed, statusSkipped}

// summaryInput is what run-summary tells the run's page about.
type summaryInput struct {
	latest     string
	waitingPR  int
	check      string
	repository string
}

// runSummary prints the markdown a run appends to its job summary
// (forsgren#40): the version that built the page, the latest release and
// where the update stands. The run page is private to the repository, so the
// waiting pull request is linked. A flag it cannot use is a usage error that
// prints nothing; the workflow never lets the summary fail the run.
func runSummary(args []string, stdout, stderr io.Writer) int {
	in, ok := summaryFlags(args, stderr)
	if !ok {
		return 2
	}
	_, _ = fmt.Fprint(stdout, in.markdown())
	return 0
}

// summaryFlags parses run-summary's arguments. It returns false once the
// usage error, naming the flag, is on stderr.
func summaryFlags(args []string, stderr io.Writer) (summaryInput, bool) {
	flags := newFlags("run-summary", stderr)
	var in summaryInput
	flags.StringVar(&in.latest, "latest", "", "the newest forsgren release, empty or not a version when unknown")
	flags.IntVar(&in.waitingPR, "waiting-pr", 0, "the open Dependabot pull request for it, 0 for none")
	flags.StringVar(&in.check, "pr-check", "", "how the pull request lookup went: "+strings.Join(statuses, ", "))
	flags.StringVar(&in.repository, "repository", "", "the installation's owner/name, for the pull request's link")
	if err := flags.Parse(args); err != nil {
		return in, false
	}
	switch {
	case !slices.Contains(statuses, in.check):
		_, _ = fmt.Fprintf(stderr, "run-summary: --pr-check must be one of %s, got %q\n", strings.Join(statuses, ", "),
			in.check)
	case in.waitingPR > 0 && in.repository == "":
		_, _ = fmt.Fprintln(stderr, "run-summary: --repository <owner/name> is required with --waiting-pr, which it links")
	default:
		return in, true
	}
	return in, false
}

// markdown is the summary.
func (in summaryInput) markdown() string {
	latest, known := page.ReleaseVersion(in.latest)
	if !known {
		latest = "unknown"
	}
	return "## forsgren\n\n- Built with: forsgren " + version + "\n- Latest release: " + latest +
		"\n- Update: " + in.update(latest, known) + "\n"
}

// update says where the update stands.
func (in summaryInput) update(latest string, known bool) string {
	if !known {
		return "unknown (the latest release could not be read)"
	}
	if (page.Data{Version: version, Latest: latest}).Update() == "" {
		return "up to date"
	}
	if in.waitingPR > 0 {
		return latest + " is waiting in pull request [#" + strconv.Itoa(in.waitingPR) + "](https://github.com/" +
			strings.Trim(in.repository, "/") + "/pull/" + strconv.Itoa(in.waitingPR) + ")"
	}
	return latest + " is available; " + in.pullRequestState()
}

// pullRequestState says what is known of the pull request when none waits.
func (in summaryInput) pullRequestState() string {
	switch in.check {
	case statusNoAccess:
		return "pull-request check skipped: grant pull-requests: read in your caller to enable it"
	case statusRateLimited:
		return "the pull-request check hit GitHub's rate limit, the next run tries again"
	case statusFailed:
		return "the pull-request check failed"
	}
	return "no Dependabot pull request yet"
}
