package main

import (
	"encoding/json"
	"strconv"
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

// otherFileFiles is GitHub's answer to the files of a pull request that
// changes a README only.
const otherFileFiles = `[{"filename": "README.md", "patch": "@@ -1 +1 @@\n-old\n+new\n"}]`

// waitingPulls is GitHub's answer to the open pull requests: one per
// number, login and branch given in threes.
func waitingPulls(t *testing.T, pulls ...[3]string) string {
	t.Helper()
	items := make([]map[string]any, len(pulls))
	for i, p := range pulls {
		number, err := strconv.Atoi(p[0])
		if err != nil {
			t.Fatal(err)
		}
		items[i] = map[string]any{"number": number, "user": map[string]string{"login": p[1]},
			"head": map[string]string{"ref": p[2]}}
	}
	body, err := json.Marshal(items)
	if err != nil {
		t.Fatal(err)
	}
	return string(body)
}

// TestWaitingPullRequestIsTheHighestDependabotOneThatMovesThePin (forsgren#42):
// of the open pull requests only Dependabot's count, only one whose files move
// the pin of metrics.yml to --version, and of several the highest number wins;
// a person's pull request that moves the pin, one that moves it to another
// version or touches another file, and a person's pull request on a branch
// named like Dependabot's bump are not the waiting one.
func TestWaitingPullRequestIsTheHighestDependabotOneThatMovesThePin(t *testing.T) {
	t.Setenv("GITHUB_REPOSITORY", "acme/data")
	t.Setenv("GITHUB_TOKEN", testToken)
	const bot, person, branch = "dependabot[bot]", "acme-dev", "dependabot/github_actions/x"
	const named = "dependabot/github_actions/yveshanoulle/forsgren/dot-github/workflows/metrics.yml-0.0.10"
	cases := map[string]struct {
		pulls string
		files map[string]string
		want  string
	}{
		"another author moves the pin": {waitingPulls(t, [3]string{"4", person, branch}),
			map[string]string{"/4/files": pinFiles(t, "0.0.10")}, ""},
		"another version": {waitingPulls(t, [3]string{"4", bot, branch}),
			map[string]string{"/4/files": pinFiles(t, "0.0.11")}, ""},
		"another file": {waitingPulls(t, [3]string{"4", bot, branch}),
			map[string]string{"/4/files": otherFileFiles}, ""},
		"a person on a branch named like the bump": {waitingPulls(t, [3]string{"4", person, named}),
			map[string]string{"/4/files": pinFiles(t, "0.0.10")}, ""},
		"the highest of several": {waitingPulls(t, [3]string{"5", bot, branch}, [3]string{"12", bot, branch},
			[3]string{"20", bot, branch}),
			map[string]string{"/12/files": pinFiles(t, "0.0.10"), "/5/files": pinFiles(t, "0.0.10"),
				"/20/files": pinFiles(t, "0.0.11")}, "12\n"},
	}
	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			bodies := map[string]string{waitingPath: tc.pulls}
			for path, body := range tc.files {
				bodies[waitingPath+path] = body
			}
			fakeAPI(t, bodies, 0)
			wantLookup(t, tc.want, "", "waiting-pull-request", "--version", "0.0.10")
		})
	}
}
