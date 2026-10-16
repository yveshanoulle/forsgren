package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"slices"
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

// reply is one answer of routedAPI: its status, headers and body.
type reply struct {
	code   int
	header http.Header
	body   string
}

// routedAPI serves an answer per path, 404 for the others, and an answer
// that names a next page of itself for a path in endless, so the client
// stops at its page limit.
func routedAPI(t *testing.T, routes map[string]reply, endless ...string) {
	t.Helper()
	serveAPI(t, func(w http.ResponseWriter, r *http.Request) {
		answer, ok := routes[r.URL.Path]
		if !ok {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		for name, values := range answer.header {
			w.Header()[name] = values
		}
		if slices.Contains(endless, r.URL.Path) {
			w.Header().Set("Link", fmt.Sprintf(`<%s%s?page=%d>; rel="next"`, githubAPI, r.URL.Path, len(r.URL.RawQuery)+2))
		}
		w.WriteHeader(max(answer.code, http.StatusOK))
		_, _ = io.WriteString(w, answer.body)
	})
}

// onePull is GitHub's answer to the open pull requests: one of Dependabot's,
// number 7.
func onePull(t *testing.T) string {
	t.Helper()
	return waitingPulls(t, [3]string{"7", "dependabot[bot]", "dependabot/github_actions/x"})
}

// TestWaitingPullRequestStatusFollowsAFailedFilesRead (forsgren#42): when the
// files of a candidate cannot be read the lookup is one that failed, as when
// the list cannot be read: nothing on stdout, exit 0, the status no-access for
// the 403 of a token without pull-requests: read, rate-limited for GitHub's
// rate limit and failed for anything else, and the stderr note names the
// permission for the 403.
func TestWaitingPullRequestStatusFollowsAFailedFilesRead(t *testing.T) {
	t.Setenv("GITHUB_REPOSITORY", "acme/data")
	t.Setenv("GITHUB_TOKEN", testToken)
	noneLeft := http.Header{"X-Ratelimit-Remaining": {"0"}}
	cases := map[string]struct {
		files  reply
		status string
		note   string
	}{
		"no permission": {reply{code: 403, body: `{"message":"no"}`}, "no-access",
			"the job's token needs pull-requests: read"},
		"rate limit":   {reply{code: 403, header: noneLeft, body: `{"message":"limit"}`}, "rate-limited", "rate limit"},
		"server error": {reply{code: 500, body: `{"message":"boom"}`}, "failed", "waiting pull request"},
	}
	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			routedAPI(t, map[string]reply{waitingPath: {body: onePull(t)}, waitingPath + "/7/files": tc.files})
			path := filepath.Join(t.TempDir(), "status")
			wantLookup(t, "", tc.note, "waiting-pull-request", "--version", "0.0.10", "--status", path)
			if status, err := os.ReadFile(filepath.Clean(path)); err != nil || string(status) != tc.status {
				t.Errorf("want the status %q, got %q (%v)", tc.status, status, err)
			}
		})
	}
}

// TestWaitingPullRequestWithMoreFilesThanWereReadIsNotAMatch (forsgren#42):
// GitHub cuts the files of a pull request at the client's page limit; a
// pull request whose files were cut is noted on stderr and is not the
// waiting one, even when the pin moves in the files read, and the other
// candidates are still checked.
func TestWaitingPullRequestWithMoreFilesThanWereReadIsNotAMatch(t *testing.T) {
	t.Setenv("GITHUB_REPOSITORY", "acme/data")
	t.Setenv("GITHUB_TOKEN", testToken)
	pulls := waitingPulls(t, [3]string{"6", "dependabot[bot]", "dependabot/github_actions/x"},
		[3]string{"9", "dependabot[bot]", "dependabot/github_actions/y"})
	routedAPI(t, map[string]reply{waitingPath: {body: pulls}, waitingPath + "/6/files": {body: pinFiles(t, "0.0.10")},
		waitingPath + "/9/files": {body: pinFiles(t, "0.0.10")}}, waitingPath+"/9/files")
	wantLookup(t, "6\n", "waiting-pull-request: pull request #9 has more files than were read, so it is not looked at",
		"waiting-pull-request", "--version", "0.0.10")
}
