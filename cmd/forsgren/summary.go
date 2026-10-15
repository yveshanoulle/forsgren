package main

import (
	"fmt"
	"io"
	"slices"
	"strconv"
	"strings"
	"time"

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
	needsCheck string
	repository string
	tokenFile  string
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
	_, _ = fmt.Fprint(stdout, in.markdown(stderr))
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
	flags.StringVar(&in.needsCheck, "needs-check", "",
		"how the setup issue went: ok, no-access, rate-limited or failed (optional)")
	flags.StringVar(&in.repository, "repository", "", "the installation's owner/name, for the pull request's link")
	flags.StringVar(&in.tokenFile, "token-expiry", "",
		"the file collect --token-expiry wrote, for the token's days left (optional)")
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
func (in summaryInput) markdown(stderr io.Writer) string {
	latest, known := page.ReleaseVersion(in.latest)
	if !known {
		latest = "unknown"
	}
	return "## forsgren\n\n- Built with: forsgren " + version + "\n- Latest release: " + latest +
		"\n- Update: " + in.update(latest, known) + "\n" +
		in.token() + in.setup(stderr)
}

// tokenUnknown is the Token line for a run with no readable expiry date: a
// token that has none, or a collect that failed before it learned one.
const tokenUnknown = "- Token: days left unknown: GitHub named no expiry date in this run " +
	"(a token without an expiry date, or collect could not ask: see the failed collect step)\n"

// token says how long FORSGREN_TOKEN is still valid, from the date collect
// wrote to --token-expiry (forsgren#185, decision #186): whole days from one
// day left, whole hours under a day, "less than an hour" under an hour or
// once the date has passed mid-run. Nothing without --token-expiry; an
// unreadable file is the unknown line.
func (in summaryInput) token() string {
	if in.tokenFile == "" {
		return ""
	}
	expiry, known := readTokenExpiry(in.tokenFile)
	if !known {
		return tokenUnknown
	}
	until := expiry.UTC().Format("2006-01-02 15:04 UTC")
	left := expiry.Sub(now())
	switch {
	case left >= 24*time.Hour:
		return "- Token: valid for " + more(int(left/(24*time.Hour)), "day") + " (until " +
			expiry.UTC().Format(time.DateOnly) + ")\n"
	case left >= time.Hour:
		return "- Token: valid for " + more(int(left/time.Hour), "hour") + " (until " + until + ")\n"
	}
	return "- Token: valid for less than an hour (until " + until + ")\n"
}

// more is "N more unit", the unit in the plural unless N is 1.
func more(n int, unit string) string {
	if n != 1 {
		unit += "s"
	}
	return strconv.Itoa(n) + " more " + unit
}

// setupConfig is the config run-summary reads the config keys of, where the
// workflow checks it out.
const setupConfig = "forsgren.config.yml"

// setupFailures say why the setup issue could not be written, by how
// check-needs' write went (the values of --needs-check, ok aside).
var setupFailures = map[string]string{
	statusNoAccess:    " for lack of `issues: write`",
	statusRateLimited: " because of GitHub's rate limit",
	statusFailed:      "",
}

// setup says where the setup issue stands: nothing without --needs-check or
// with a value it does not know, and, when the issue could not be written,
// what this version needs, which it computes from the checkout the way
// check-needs does (forsgren#73).
func (in summaryInput) setup(stderr io.Writer) string {
	if in.needsCheck == statusOK {
		return "- Setup: in place, or the setup issue says what is missing\n"
	}
	reason, known := setupFailures[in.needsCheck]
	if !known {
		return ""
	}
	line := "- Setup: the setup issue could not be written" + reason + "; this version needs:\n"
	missing, err := missingNeeds("run-summary", setupConfig, stderr)
	if err != nil {
		_, _ = fmt.Fprintf(stderr, "run-summary: the needs could not be checked: %v\n", err)
	}
	for _, n := range missing {
		line += "  - " + n.Steps + "\n"
	}
	return line
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
