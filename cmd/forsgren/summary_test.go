package main

import (
	"os"
	"path/filepath"
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
		{"available", []string{"--latest", "0.3.3", "--pr-check", "ok"},
			summaryOf("0.3.3", "0.3.3 is available; no Dependabot pull request yet")},
		{"waiting", []string{"--latest", "0.3.3", "--waiting-pr", "7", "--pr-check", "ok", "--repository", "acme/data"},
			summaryOf("0.3.3", "0.3.3 is waiting in pull request [#7](https://github.com/acme/data/pull/7)")},
		{"no access", []string{"--latest", "0.3.3", "--pr-check", "no-access"},
			summaryOf("0.3.3", "0.3.3 is available; "+skipped)},
		{"check failed", []string{"--latest", "0.3.3", "--pr-check", "failed"},
			summaryOf("0.3.3", "0.3.3 is available; the pull-request check failed")},
		{"rate limited", []string{"--latest", "0.3.3", "--pr-check", "rate-limited"},
			summaryOf("0.3.3", "0.3.3 is available; "+rateLimited)},
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

// TestRunSummaryRefusesWhatItCannotTell (forsgren#40, step 6): a pr-check
// that is none of ok, no-access, rate-limited, failed or skipped, or a waiting pull request
// with no repository to link: a usage error that says which flag and prints
// nothing (the workflow never lets that fail the run).
func TestRunSummaryRefusesWhatItCannotTell(t *testing.T) {
	cases := map[string][]string{
		"--pr-check":   {"run-summary", "--latest", "0.3.3", "--pr-check", "banana"},
		"--repository": {"run-summary", "--latest", "0.3.3", "--waiting-pr", "7", "--pr-check", "ok"},
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
