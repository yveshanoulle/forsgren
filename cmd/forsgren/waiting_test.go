package main

import (
	"encoding/json"
	"testing"
)

// pinFiles is GitHub's answer to a pull request's files: forsgren.yml, whose
// pin of metrics.yml moves to version (without the v) from 0.0.1.
func pinFiles(t *testing.T, version string) string {
	t.Helper()
	const uses = "    uses: yveshanoulle/forsgren/.github/workflows/metrics.yml@"
	const sha = "437c858abd71d6f33e6f714af7984de3855d8e73"
	patch := "@@ -14 +14 @@\n-" + uses + sha + " # v0.0.1\n+" + uses + sha + " # v" + version + "\n"
	body, err := json.Marshal([]map[string]string{{"filename": ".github/workflows/forsgren.yml", "patch": patch}})
	if err != nil {
		t.Fatal(err)
	}
	return string(body)
}

// TestWaitingPullRequestIsFoundByWhatItChangesNotByItsBranch (forsgren#42):
// Dependabot's pull request on a grouped-update branch, which the branch name
// of a plain bump does not match, is the waiting one because its files move
// the pin of metrics.yml to --version; a version it does not move to finds none.
func TestWaitingPullRequestIsFoundByWhatItChangesNotByItsBranch(t *testing.T) {
	t.Setenv("GITHUB_REPOSITORY", "acme/data")
	t.Setenv("GITHUB_TOKEN", testToken)
	fakeAPI(t, map[string]string{
		waitingPath: `[{"number": 9, "user": {"login": "dependabot[bot]"},
		  "head": {"ref": "dependabot/github_actions/group-abc123"}}]`,
		waitingPath + "/9/files": pinFiles(t, "0.0.10"),
	}, 0)
	wantLookup(t, "9\n", "", "waiting-pull-request", "--version", "0.0.10")
	wantLookup(t, "", "", "waiting-pull-request", "--version", "0.0.11")
}

// TestWaitingPullRequestWhoseFilesCannotBeReadIsALookupThatFailed
// (forsgren#42): a candidate whose files GitHub does not answer makes the
// lookup fail like any other, nothing on stdout and why on stderr.
func TestWaitingPullRequestWhoseFilesCannotBeReadIsALookupThatFailed(t *testing.T) {
	t.Setenv("GITHUB_REPOSITORY", "acme/data")
	t.Setenv("GITHUB_TOKEN", testToken)
	fakeAPI(t, map[string]string{waitingPath: dependabotPulls}, 0)
	wantLookup(t, "", "waiting pull request", "waiting-pull-request", "--version", "0.0.10")
}
