package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// summaryOf is the run summary for the moment of the run, as the clock of the
// test gives it (forsgren#194), the version that built the page, the latest
// release as the summary shows it, and the update line. A test that compares a
// whole summary pins the clock first.
func summaryOf(latest, update string) string {
	return "## forsgren\n\n- Run: " + now().UTC().Format("2006-01-02 15:04 UTC") + "\n- Built with: forsgren " +
		version + "\n- Latest release: " + latest + "\n- Update: " + update + "\n"
}

// TestRunSummaryNamesTheRunMomentInUTC (forsgren#194): the first line of the
// summary, before the version that built the page, is the moment the summary is
// written, to the minute, in UTC whatever zone the clock is in, so a summary
// pasted somewhere says when it is from.
func TestRunSummaryNamesTheRunMomentInUTC(t *testing.T) {
	pinClock(t, time.Date(2026, time.October, 4, 1, 30, 59, 0, time.FixedZone("CEST", 2*60*60)))
	_, stdout, _ := runCommand("run-summary", "--latest", version, "--pr-check", "ok")
	want := "## forsgren\n\n- Run: 2026-10-03 23:30 UTC\n- Built with: forsgren " + version + "\n"
	if !strings.HasPrefix(stdout, want) {
		t.Errorf("want the summary to start with %q, got %q", want, stdout)
	}
}

// TestRunSummaryTellsWhereTheUpdateStands (forsgren#40, step 6): the
// markdown a run appends to its job summary names the version that built
// the page, the latest release, and one of the six states of the update.
// The run page is private to the repository, so the pull request is linked.
func TestRunSummaryTellsWhereTheUpdateStands(t *testing.T) {
	pinNow(t)
	const skipped = "pull-request check skipped: grant pull-requests: read in your caller to enable it"
	const rateLimited = "the pull-request check hit GitHub's rate limit, the next run tries again"
	cases := []struct {
		name string
		args []string
		want string
	}{
		{"up to date", []string{"--latest", version, "--pr-check", "ok"}, summaryOf(version, "up to date")},
		{"ahead of the latest", []string{"--latest", "0.0.1", "--pr-check", "ok"}, summaryOf("0.0.1", "up to date")},
		{"available", []string{"--latest", "1.8.4", "--pr-check", "ok"},
			summaryOf("1.8.4", "1.8.4 is available; no Dependabot pull request yet")},
		{"waiting", []string{"--latest", "1.8.4", "--waiting-pr", "7", "--pr-check", "ok", "--repository", "acme/data"},
			summaryOf("1.8.4", "1.8.4 is waiting in pull request [#7](https://github.com/acme/data/pull/7)")},
		{"no access", []string{"--latest", "1.8.4", "--pr-check", "no-access"},
			summaryOf("1.8.4", "1.8.4 is available; "+skipped)},
		{"check failed", []string{"--latest", "1.8.4", "--pr-check", "failed"},
			summaryOf("1.8.4", "1.8.4 is available; the pull-request check failed")},
		{"rate limited", []string{"--latest", "1.8.4", "--pr-check", "rate-limited"},
			summaryOf("1.8.4", "1.8.4 is available; "+rateLimited)},
		{"pull request list truncated", []string{"--latest", "1.8.4", "--pr-check", "truncated"},
			summaryOf("1.8.4", "1.8.4 is available; unknown (pull request list truncated)")},
		{"truncated, waiting", []string{"--latest", "1.8.4", "--waiting-pr", "7", "--pr-check", "truncated",
			"--repository", "acme/data"},
			summaryOf("1.8.4", "1.8.4 is waiting in pull request [#7](https://github.com/acme/data/pull/7)")},
		{"truncated, up to date", []string{"--latest", version, "--pr-check", "truncated"},
			summaryOf(version, "up to date")},
		{"no access, up to date", []string{"--latest", version, "--pr-check", "no-access"},
			summaryOf(version, "up to date")},
		{"latest unknown", []string{"--latest", "", "--pr-check", "skipped"},
			summaryOf("unknown", "unknown (the latest release could not be read)")},
		{"latest not a version", []string{"--latest", "banana", "--pr-check", "skipped"},
			summaryOf("unknown", "unknown (the latest release could not be read)")},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			code, stdout, stderr := runCommand(append([]string{"run-summary"}, c.args...)...)
			if code != 0 || stdout != c.want {
				t.Errorf("want exit 0 and:\n%s\ngot %d, %q, stderr %q", c.want, code, stdout, stderr)
			}
		})
	}
}

// setupCase is a row of TestRunSummaryReportsTheSetupIssue: the summary of an
// installation without issues: write, run with --needs-check check, holds
// every part of want and none of wantNot.
type setupCase struct {
	name, check string
	want        []string
	wantNot     []string
}

// wantParts fails the test for each part of parts that got holds when it
// should not, or lacks when it should.
func wantParts(t *testing.T, got string, parts []string, holds bool) {
	t.Helper()
	for _, part := range parts {
		if strings.Contains(got, part) != holds {
			t.Errorf("want the summary to hold %q: %t, got %q", part, holds, got)
		}
	}
}

// run runs run-summary for the row and checks its summary.
func (c setupCase) run(t *testing.T) {
	t.Helper()
	setVersion(t, "0.4.0")
	installationWithoutIssuesWrite(t)
	code, stdout, stderr := runCommand("run-summary", "--latest", version, "--pr-check", "ok",
		"--needs-check", c.check)
	if code != 0 {
		t.Fatalf("want exit 0, got %d, stderr %q", code, stderr)
	}
	wantParts(t, stdout, c.want, true)
	wantParts(t, stdout, c.wantNot, false)
}

// TestRunSummaryReportsTheSetupIssue (forsgren#73, step 17): with
// --needs-check ok the summary says the setup is in place or the setup issue
// says what is missing, and lists nothing; with no-access, rate-limited or
// failed it says why the setup issue could not be written and lists the Steps
// of every need missing from the checkout, which run-summary computes itself.
// The test pins the version at 0.4.0, the release that introduced the need.
func TestRunSummaryReportsTheSetupIssue(t *testing.T) {
	const ok = "- Setup: in place, or the setup issue says what is missing"
	const noAccess = "- Setup: the setup issue could not be written for lack of `issues: write`; this version needs:"
	const rateLimited = "- Setup: the setup issue could not be written because of GitHub's rate limit; this version needs:"
	const failed = "- Setup: the setup issue could not be written; this version needs:"
	const steps = "Add `issues: write` to the `permissions:` of the forsgren job in .github/workflows/forsgren.yml"
	cases := []setupCase{
		{"no access", "no-access", []string{noAccess, steps}, []string{ok}},
		{"ok", "ok", []string{ok}, []string{steps, noAccess}},
		{"rate limited", "rate-limited", []string{rateLimited, steps}, []string{ok, noAccess}},
		{"failed", "failed", []string{failed, steps}, []string{ok, noAccess}},
		{"not given", "", nil, []string{"- Setup:", steps}},
	}
	for _, c := range cases {
		t.Run(c.name, c.run)
	}
}

// TestRunSummaryNamesAVersionWithNoNeeds (forsgren#73, step 17): a version
// whose needs cannot be read lists none, with a note on stderr, and the
// summary still says the setup issue could not be written.
func TestRunSummaryNamesAVersionWithNoNeeds(t *testing.T) {
	setVersion(t, "banana")
	installationWithoutIssuesWrite(t)
	code, stdout, stderr := runCommand("run-summary", "--latest", "", "--pr-check", "skipped",
		"--needs-check", "failed")
	if code != 0 {
		t.Errorf("want exit 0, got %d", code)
	}
	wantParts(t, stdout, []string{"- Setup: the setup issue could not be written;"}, true)
	if !strings.Contains(stderr, "the needs could not be checked") {
		t.Errorf("stderr %q, want a note that the needs could not be checked", stderr)
	}
}

// TestRunSummaryNotesAnUnreadableConfigAsItsOwn (forsgren#73, step 19): when
// run-summary computes the needs and the config cannot be read, its note on
// stderr starts with run-summary:, never with check-needs:.
func TestRunSummaryNotesAnUnreadableConfigAsItsOwn(t *testing.T) {
	setVersion(t, "0.4.0")
	installationWithoutIssuesWrite(t)
	if err := os.Remove("forsgren.config.yml"); err != nil {
		t.Fatal(err)
	}
	code, _, stderr := runCommand("run-summary", "--latest", version, "--pr-check", "ok",
		"--needs-check", "failed")
	if code != 0 {
		t.Errorf("want exit 0, got %d", code)
	}
	if !strings.HasPrefix(stderr, "run-summary:") || strings.Contains(stderr, "check-needs:") {
		t.Errorf("stderr %q, want it to start with run-summary: and not name check-needs:", stderr)
	}
}

// TestRunSummaryRefusesWhatItCannotTell (forsgren#40, step 6): a pr-check
// that is none of ok, no-access, rate-limited, failed or skipped, or a waiting pull request
// with no repository to link: a usage error that says which flag and prints
// nothing (the workflow never lets that fail the run).
func TestRunSummaryRefusesWhatItCannotTell(t *testing.T) {
	cases := map[string][]string{
		"--pr-check":   {"run-summary", "--latest", "1.8.4", "--pr-check", "banana"},
		"--repository": {"run-summary", "--latest", "1.8.4", "--waiting-pr", "7", "--pr-check", "ok"},
	}
	for flag, args := range cases {
		wantExit(t, exit{2, "", flag}, args...)
	}
}

// wantStatus runs the lookup for 0.0.10 with --status and fails the test
// unless the file it wrote says want.
func wantStatus(t *testing.T, want string) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "status")
	if code, _, stderr := runCommand("waiting-pull-request", "--version", "0.0.10", "--status", path); code != 0 {
		t.Errorf("want exit 0, got %d, %q", code, stderr)
	}
	got, err := os.ReadFile(filepath.Clean(path))
	if err != nil || string(got) != want {
		t.Errorf("want the status file to say %q, got %q, %v", want, got, err)
	}
}

// TestWaitingPullRequestSaysHowTheLookupWent (forsgren#40, step 6): with
// --status <path> the lookup writes how it went, besides what it prints: ok
// (a number or none), no-access (the 403 of a token without pull-requests:
// read) or failed (anything else, no GITHUB_REPOSITORY included). Its exit
// status stays 0 whatever the status.
func TestWaitingPullRequestSaysHowTheLookupWent(t *testing.T) {
	t.Setenv("GITHUB_REPOSITORY", "acme/data")
	fakeAPI(t, dependabotAPI(t), 0)
	wantStatus(t, "ok")
	fakeAPI(t, map[string]string{waitingPath: `[]`}, 0)
	wantStatus(t, "ok")
	fakeAPI(t, map[string]string{waitingPath: `{"message":"no"}`}, 403)
	wantStatus(t, "no-access")
	fakeAPI(t, map[string]string{waitingPath: `{"message":"no"}`}, 500)
	wantStatus(t, "failed")
	t.Setenv("GITHUB_REPOSITORY", "")
	wantStatus(t, "failed")
}

// TestTheSummaryCommandsRefuseAnUnknownFlag (forsgren#40, step 6): a flag
// they do not have is a usage error, exit 2, with nothing printed.
func TestTheSummaryCommandsRefuseAnUnknownFlag(t *testing.T) {
	for _, command := range []string{"run-summary", "waiting-pull-request"} {
		if code, stdout, _ := runCommand(command, "--nonsense"); code != 2 || stdout != "" {
			t.Errorf("%s: want exit 2 and no stdout, got %d, %q", command, code, stdout)
		}
	}
}

// TestAStatusThatCannotBeWrittenIsANoteNotAnError (forsgren#40, step 6): the
// lookup still exits 0 and prints its number; the workflow reads a missing
// status as failed.
func TestAStatusThatCannotBeWrittenIsANoteNotAnError(t *testing.T) {
	t.Setenv("GITHUB_REPOSITORY", "acme/data")
	fakeAPI(t, dependabotAPI(t), 0)
	missing := filepath.Join(t.TempDir(), "no", "such", "dir", "status")
	wantLookup(t, "7\n", "cannot write the status", "waiting-pull-request", "--version", "0.0.10", "--status", missing)
}

// TestRunSummaryTellsHowLongTheTokenIsValid (forsgren#185, decision #186,
// forsgren#194): the Token line counts whole days from one day left, whole
// hours under a day, says less than an hour under an hour (or once the date
// has passed mid-run), tells the run's own token from one with no expiry date,
// and says collect could not ask when the file is missing or unreadable.
// Without --token-expiry there is no line.
func TestRunSummaryTellsHowLongTheTokenIsValid(t *testing.T) {
	old := now
	now = func() time.Time { return time.Date(2026, 10, 1, 12, 0, 0, 0, time.UTC) }
	t.Cleanup(func() { now = old })
	const unknown = "- Token: unknown: collect could not ask GitHub: see the failed collect step\n"
	const ownLine = "- Token: the run's own token (GITHUB_TOKEN), renewed every run; nothing expires\n"
	const unreadable = "- Token: unknown: GitHub sent an expiry date forsgren cannot read; " +
		"see the note in the collect step\n"
	const noDate = "- Token: no expiry date: a personal token set to no expiration (or more than a year); " +
		"a date under a year makes forsgren warn before it runs out\n"
	const lessThanAnHour = "- Token: valid for less than an hour (until "
	cases := []struct{ name, file, want string }{
		{"days", "2026-10-11T12:00:00Z\n", "- Token: valid for 10 more days (until 2026-10-11)\n"},
		{"days rounded down", "2026-10-03T11:59:59Z\n", "- Token: valid for 1 more day (until 2026-10-03)\n"},
		{"hours", "2026-10-02T11:59:59Z\n", "- Token: valid for 23 more hours (until 2026-10-02 11:59 UTC)\n"},
		{"1 hour rounded down", "2026-10-01T13:59:59Z\n", "- Token: valid for 1 more hour (until 2026-10-01 13:59 UTC)\n"},
		{"less than an hour", "2026-10-01T12:59:59Z\n", lessThanAnHour + "2026-10-01 12:59 UTC)\n"},
		{"already passed", "2026-10-01T11:00:00Z\n", lessThanAnHour + "2026-10-01 11:00 UTC)\n"},
		{"run token", "no-expiry run-token\n", ownLine},
		{"no expiry date", "no-expiry\n", noDate},
		{"unreadable", "unreadable\n", unreadable},
		{"not a date", "banana\n", unknown},
		{"no file", "", unknown},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "token-expiry")
			if c.file != "" {
				writeFile(t, path, c.file)
			}
			_, stdout, _ := runCommand("run-summary", "--latest", version, "--pr-check", "ok", "--token-expiry", path)
			if want := summaryOf(version, "up to date") + c.want; stdout != want {
				t.Errorf("want %q, got %q", want, stdout)
			}
		})
	}
}

// TestRunSummaryHasNoTokenLineWithoutTheFlag (forsgren#185): a caller that
// does not pass --token-expiry gets the summary it always had.
func TestRunSummaryHasNoTokenLineWithoutTheFlag(t *testing.T) {
	pinNow(t)
	_, stdout, _ := runCommand("run-summary", "--latest", version, "--pr-check", "ok")
	if want := summaryOf(version, "up to date"); stdout != want {
		t.Errorf("want %q, got %q", want, stdout)
	}
}

// writeFile writes content to path or fails the test.
func writeFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
}

// checkoutWith makes the working directory a checkout whose
// .github/dependabot.yml holds dependabot ("" for none), and returns the file
// latest-release --published would write with published ("" for none).
func checkoutWith(t *testing.T, dependabot, published string) string {
	t.Helper()
	t.Chdir(t.TempDir())
	if dependabot != "" {
		if err := os.MkdirAll(".github", 0o750); err != nil {
			t.Fatal(err)
		}
		writeFile(t, dependabotFile, dependabot)
	}
	file := filepath.Join(t.TempDir(), "latest-published")
	if published != "" {
		writeFile(t, file, published+"\n")
	}
	return file
}

// actionsCooldown is a dependabot.yml whose github-actions update waits days.
func actionsCooldown(days string) string {
	return "version: 2\nupdates:\n  - package-ecosystem: github-actions\n    cooldown:\n      default-days: " + days + "\n"
}

// TestTheUpdateLineNamesTheDependabotCooldown (forsgren#194, #195): a newer release
// with no pull request yet is waiting for the cooldown, with the date it ends
// (the publish time plus the days, in UTC), while the cooldown is running; with
// no days (default-days: 0), the date past, no file, a file that says nothing or a publish time
// that is unknown, it is today's "no Dependabot pull request yet". The clock
// of these cases is 2026-10-15 15:10 UTC.
func TestTheUpdateLineNamesTheDependabotCooldown(t *testing.T) {
	const (
		fresh   = "2026-10-15T09:00:00Z"
		none    = "no Dependabot pull request yet"
		waiting = "waiting for the 3-day cooldown until 2026-10-18"
	)
	cases := []struct{ name, dependabot, published, want string }{
		{"waiting", actionsCooldown("3"), fresh, waiting},
		{"the template's", templateDependabot, fresh, waiting},
		{"in UTC", actionsCooldown("3"), "2026-10-15T23:30:00-03:00", "waiting for the 3-day cooldown until 2026-10-19"},
		{"zero days", actionsCooldown("0"), fresh, none},
		{"no cooldown key", "version: 2\nupdates:\n  - package-ecosystem: github-actions\n", fresh, waiting},
		{"no github-actions update", "version: 2\nupdates: []\n", fresh, none},
		{"no dependabot file", "", fresh, none},
		{"unreadable file", "updates: [", fresh, none},
		{"past the date", actionsCooldown("3"), "2026-10-01T09:00:00Z", none},
		{"publish time unknown", actionsCooldown("3"), "", none},
		{"publish time not a time", actionsCooldown("3"), "yesterday", none},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			pinClock(t, time.Date(2026, 10, 15, 15, 10, 0, 0, time.UTC))
			file := checkoutWith(t, c.dependabot, c.published)
			_, stdout, _ := runCommand("run-summary", "--latest", "1.8.4", "--pr-check", "ok", "--latest-published", file)
			if want := summaryOf("1.8.4", "1.8.4 is available; "+c.want); stdout != want {
				t.Errorf("want %q, got %q", want, stdout)
			}
		})
	}
}

// TestTheCooldownIsOnlyNamedWhereNoPullRequestWaits (forsgren#194): a waiting
// pull request, a check that did not work and an up to date installation keep
// their own Update lines, whatever the cooldown says.
func TestTheCooldownIsOnlyNamedWhereNoPullRequestWaits(t *testing.T) {
	pinClock(t, time.Date(2026, 10, 15, 15, 10, 0, 0, time.UTC))
	file := checkoutWith(t, templateDependabot, "2026-10-15T09:00:00Z")
	cases := []struct {
		name string
		args []string
		want string
	}{
		{"waiting", []string{"--latest", "1.8.4", "--waiting-pr", "7", "--pr-check", "ok", "--repository", "acme/data"},
			"1.8.4 is waiting in pull request [#7](https://github.com/acme/data/pull/7)"},
		{"check failed", []string{"--latest", "1.8.4", "--pr-check", "failed"},
			"1.8.4 is available; the pull-request check failed"},
		{"up to date", []string{"--latest", version, "--pr-check", "ok"}, "up to date"},
	}
	for _, c := range cases {
		args := append([]string{"run-summary", "--latest-published", file}, c.args...)
		if _, stdout, _ := runCommand(args...); !strings.Contains(stdout, "- Update: "+c.want+"\n") {
			t.Errorf("%s: want the Update line %q, got %q", c.name, c.want, stdout)
		}
	}
}
