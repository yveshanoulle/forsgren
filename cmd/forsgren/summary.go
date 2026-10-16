package main

import (
	"fmt"
	"io"
	"slices"
	"strconv"
	"strings"
	"time"

	installreadme "github.com/yveshanoulle/forsgren/install"
	"github.com/yveshanoulle/forsgren/internal/page"
)

// The ways the lookup of the waiting pull request went, as waiting-pull-
// request writes them to --status and run-summary reads them from
// --pr-check; rate-limited is GitHub's rate limit, never a missing
// permission; truncated is a list of open pull requests cut at the page limit
// with no waiting pull request in it (forsgren#203); skipped is a run with no
// latest release to look one up for.
const (
	statusOK          = "ok"
	statusNoAccess    = "no-access"
	statusRateLimited = "rate-limited"
	statusTruncated   = "truncated"
	statusFailed      = "failed"
	statusSkipped     = "skipped"
)

// statuses are the values of --pr-check.
var statuses = []string{statusOK, statusNoAccess, statusRateLimited, statusTruncated, statusFailed, statusSkipped}

// summaryInput is what run-summary tells the run's page about.
type summaryInput struct {
	latest     string
	waitingPR  int
	check      string
	needsCheck string
	// readme is how install-readme went, created, replaced or unchanged
	// (forsgren#110).
	readme     string
	repository string
	tokenFile  string
	// published is the file latest-release --published wrote, for the
	// cooldown the Update line names (forsgren#194).
	published string
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
	flags.StringVar(&in.readme, "readme", "",
		"how install-readme went: created, replaced or unchanged (optional)")
	flags.StringVar(&in.repository, "repository", "", "the installation's owner/name, for the pull request's link")
	flags.StringVar(&in.tokenFile, "token-expiry", "",
		"the file collect --token-expiry wrote, for the token's days left (optional)")
	flags.StringVar(&in.published, "latest-published", "",
		"the file latest-release --published wrote, for the Dependabot cooldown (optional)")
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

// runLayout is the moment the summary names, to the minute in UTC
// (forsgren#194), and the end of a token valid for less than a day.
const runLayout = "2006-01-02 15:04 UTC"

// markdown is the summary: the moment it is written, so a summary pasted
// somewhere says when it is from (forsgren#194), then the versions and the rest.
func (in summaryInput) markdown(stderr io.Writer) string {
	latest, _ := in.latestRelease()
	lines := []string{
		"Run: " + now().UTC().Format(runLayout),
		"Built with: forsgren " + version,
		"Latest release: " + latest,
		"Update: " + in.update(),
	}
	return "## forsgren\n\n- " + strings.Join(lines, "\n- ") + "\n" + in.token() + in.setup(stderr) + in.readmeLine()
}

// latestRelease is the newest release as --latest names it, and whether it is
// known: "unknown" when --latest is empty or not a version.
func (in summaryInput) latestRelease() (string, bool) {
	latest, known := page.ReleaseVersion(in.latest)
	if !known {
		return "unknown", false
	}
	return latest, true
}

// tokenWords say what the Token line tells of a token with no date to count
// from (forsgren#194), by what the --token-expiry file holds: the run's own
// token, one that answered without an expiry date, one whose header forsgren
// cannot read, and, for no word, one collect could not ask about.
var tokenWords = map[string]string{
	expiryNoneRunOwn: "the run's own token (GITHUB_TOKEN), renewed every run; nothing expires",
	expiryNone: "no expiry date: a personal token set to no expiration (or more than a year); " +
		"a date under a year makes forsgren warn before it runs out",
	expiryUnreadable: "unknown: GitHub sent an expiry date forsgren cannot read; see the note in the collect step",
	"":               "unknown: collect could not ask GitHub: see the failed collect step",
}

// token is the Token line, how long FORSGREN_TOKEN is still valid, from what
// collect wrote to --token-expiry (forsgren#185, decision #186, forsgren#194):
// validFor a date, and tokenWords for the rest, a missing or unreadable file
// being one collect could not ask about. Nothing without --token-expiry.
func (in summaryInput) token() string {
	if in.tokenFile == "" {
		return ""
	}
	expiry := readExpiryFile(in.tokenFile)
	state := tokenWords[expiry.word]
	if expiry.dated {
		state = validFor(expiry.date)
	}
	return "- Token: " + state + "\n"
}

// validFor is how long a token that expires on expiry is still valid: whole
// days, to the date, from one day left; whole hours under a day and "less than
// an hour" under an hour or once the date has passed mid-run, both to the
// minute.
func validFor(expiry time.Time) string {
	left := expiry.Sub(now())
	span, until := "less than an hour", expiry.UTC().Format(runLayout)
	switch {
	case left >= 24*time.Hour:
		span, until = more(int(left/(24*time.Hour)), "day"), expiry.UTC().Format(time.DateOnly)
	case left >= time.Hour:
		span = more(int(left/time.Hour), "hour")
	}
	return "valid for " + span + " (until " + until + ")"
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

// readmeWords say what the README line tells for each word install-readme
// prints (the values of --readme, installreadme's outcomes), %s standing for
// the version that wrote the README.
var readmeWords = map[string]string{
	installreadme.Created:   "created from forsgren %s's",
	installreadme.Replaced:  "replaced with forsgren %s's",
	installreadme.Unchanged: "unchanged",
}

// readmeLine says what happened to the installation's README (forsgren#110):
// nothing without --readme or with a word it does not know, as setup does.
func (in summaryInput) readmeLine() string {
	words, known := readmeWords[in.readme]
	if !known {
		return ""
	}
	return "- README: " + strings.Replace(words, "%s", version, 1) + "\n"
}

// update says where the update stands.
func (in summaryInput) update() string {
	latest, known := in.latestRelease()
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

// cooldownNote says that the release is waiting for Dependabot's cooldown,
// until the day it ends in UTC, while the cooldown the installation's
// dependabot.yml names is still running; false when the file names none, the
// publish time is unknown or the cooldown is over (forsgren#194).
func (in summaryInput) cooldownNote() (string, bool) {
	days := cooldownDays(dependabotFile)
	published, err := time.Parse(time.RFC3339, fileLine(in.published))
	if days == 0 || err != nil {
		return "", false
	}
	end := published.AddDate(0, 0, days)
	if !now().Before(end) {
		return "", false
	}
	return "waiting for the " + strconv.Itoa(days) + "-day cooldown until " + end.UTC().Format(time.DateOnly), true
}

// pullRequestState says what is known of the pull request when none waits.
func (in summaryInput) pullRequestState() string {
	switch in.check {
	case statusNoAccess:
		return "pull-request check skipped: grant pull-requests: read in your caller to enable it"
	case statusRateLimited:
		return "the pull-request check hit GitHub's rate limit, the next run tries again"
	case statusTruncated:
		return "unknown (pull request list truncated)"
	case statusFailed:
		return "the pull-request check failed"
	}
	if note, waiting := in.cooldownNote(); waiting {
		return note
	}
	return "no Dependabot pull request yet"
}
