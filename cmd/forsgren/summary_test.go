package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// summaryOf is the run summary for the version that built the page, the
// latest release as the summary shows it, and the update line.
func summaryOf(latest, update string) string {
	return "## forsgren\n\n- Built with: forsgren " + version + "\n- Latest release: " + latest + "\n- Update: " +
		update + "\n"
}

// TestRunSummaryTellsWhereTheUpdateStands (forsgren#40, step 6): the
// markdown a run appends to its job summary names the version that built
// the page, the latest release, and one of the six states of the update.
// The run page is private to the repository, so the pull request is linked.
func TestRunSummaryTellsWhereTheUpdateStands(t *testing.T) {
	const skipped = "pull-request check skipped: grant pull-requests: read in your caller to enable it"
	const rateLimited = "the pull-request check hit GitHub's rate limit, the next run tries again"
	cases := []struct {
		name string
		args []string
		want string
	}{
		{"up to date", []string{"--latest", version, "--pr-check", "ok"}, summaryOf(version, "up to date")},
		{"ahead of the latest", []string{"--latest", "0.0.1", "--pr-check", "ok"}, summaryOf("0.0.1", "up to date")},
		{"available", []string{"--latest", "0.4.1", "--pr-check", "ok"},
			summaryOf("0.4.1", "0.4.1 is available; no Dependabot pull request yet")},
		{"waiting", []string{"--latest", "0.4.1", "--waiting-pr", "7", "--pr-check", "ok", "--repository", "acme/data"},
			summaryOf("0.4.1", "0.4.1 is waiting in pull request [#7](https://github.com/acme/data/pull/7)")},
		{"no access", []string{"--latest", "0.4.1", "--pr-check", "no-access"},
			summaryOf("0.4.1", "0.4.1 is available; "+skipped)},
		{"check failed", []string{"--latest", "0.4.1", "--pr-check", "failed"},
			summaryOf("0.4.1", "0.4.1 is available; the pull-request check failed")},
		{"rate limited", []string{"--latest", "0.4.1", "--pr-check", "rate-limited"},
			summaryOf("0.4.1", "0.4.1 is available; "+rateLimited)},
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
		"--pr-check":   {"run-summary", "--latest", "0.4.1", "--pr-check", "banana"},
		"--repository": {"run-summary", "--latest", "0.4.1", "--waiting-pr", "7", "--pr-check", "ok"},
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
	fakeAPI(t, map[string]string{waitingPath: dependabotPulls}, 0)
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
	fakeAPI(t, map[string]string{waitingPath: dependabotPulls}, 0)
	missing := filepath.Join(t.TempDir(), "no", "such", "dir", "status")
	wantLookup(t, "7\n", "cannot write the status", "waiting-pull-request", "--version", "0.0.10", "--status", missing)
}
