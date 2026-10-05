package main

import (
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

// readmePatch is the patch of a change to a README, a file no caller pins
// forsgren in.
const readmePatch = "@@ -1 +1 @@\n-old\n+new\n"

// recordedAPI points the commands at a test server that gives each path its
// answer, and 404 to any other, and returns a function that lists the paths
// asked for so far.
func recordedAPI(t *testing.T, answers map[string]answer) func() []string {
	t.Helper()
	var mu sync.Mutex
	var paths []string
	serveAPI(t, func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		paths = append(paths, r.URL.Path)
		mu.Unlock()
		a, ok := answers[r.URL.Path]
		if !ok {
			a = answer{code: http.StatusNotFound, body: `{"message":"Not Found"}`}
		}
		w.WriteHeader(a.code)
		_, _ = w.Write([]byte(a.body))
	})
	return func() []string {
		mu.Lock()
		defer mu.Unlock()
		return append([]string(nil), paths...)
	}
}

// changedFiles is the answer to a pull request's files: each file's path and
// patch.
func changedFiles(t *testing.T, files ...map[string]string) answer {
	t.Helper()
	return answer{200, jsonOf(t, files)}
}

// wantLeft fails unless got is exit 1 with the one line `left for a human:
// <reason>` on stdout and nothing on stderr.
func wantLeft(t *testing.T, got outcome, reason string) {
	t.Helper()
	want := outcome{code: 1, stdout: "left for a human: " + reason + "\n"}
	if got != want {
		t.Errorf("want exit 1 and `left for a human: %s`, got %d, %q, stderr %q",
			reason, got.code, got.stdout, got.stderr)
	}
}

// TestCheckUpdateLeavesAPullRequestOfAnotherAuthorForAHuman: the guard's
// reason, which names the author, is the one line on stdout, and the exit
// status is 1.
func TestCheckUpdateLeavesAPullRequestOfAnotherAuthorForAHuman(t *testing.T) {
	answers := mergeableAnswers(t)
	answers["/repos/acme/data/pulls/7"] = answer{200, `{"user": {"login": "octocat"}}`}
	recordedAPI(t, answers)
	got := checkUpdateRun(argsOf(updateFlags(t), "config", "repo", "pull")...)
	wantLeft(t, got, `the author is "octocat", not dependabot[bot]`)
}

// TestCheckUpdateLeavesAPullRequestThatChangesMoreThanThePinForAHuman: a
// file besides the callers' pin line is named in the reason.
func TestCheckUpdateLeavesAPullRequestThatChangesMoreThanThePinForAHuman(t *testing.T) {
	answers := mergeableAnswers(t)
	answers["/repos/acme/data/pulls/7/files"] = changedFiles(t,
		map[string]string{"filename": ".github/workflows/forsgren.yml", "patch": bumpPatch},
		map[string]string{"filename": "README.md", "patch": readmePatch})
	recordedAPI(t, answers)
	got := checkUpdateRun(argsOf(updateFlags(t), "config", "repo", "pull")...)
	wantLeft(t, got, "changed besides the pin line: README.md")
}

// TestCheckUpdateAsksForNoReleaseWhenThePullRequestMovesNoPin: with no pin
// line in the diff there is no version whose release could be looked up, so
// neither the release nor its tag is asked for, and the guard's reason is
// the answer.
func TestCheckUpdateAsksForNoReleaseWhenThePullRequestMovesNoPin(t *testing.T) {
	cases := map[string]struct {
		files  answer
		reason string
	}{
		"no file changed": {changedFiles(t), "no pin line changed"},
		"only a readme": {
			changedFiles(t, map[string]string{"filename": "README.md", "patch": readmePatch}),
			"changed besides the pin line: README.md",
		},
	}
	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			answers := mergeableAnswers(t)
			answers["/repos/acme/data/pulls/7/files"] = c.files
			asked := recordedAPI(t, answers)
			got := checkUpdateRun(argsOf(updateFlags(t), "config", "repo", "pull")...)
			wantLeft(t, got, c.reason)
			for _, path := range asked() {
				if strings.Contains(path, "/releases/tags") || strings.Contains(path, "/commits/tags") {
					t.Errorf("want no request for a release or a tag, got %s", path)
				}
			}
		})
	}
}

// TestCheckUpdateLeavesAPullRequestThatMovesOnlyOneOfTwoCallersForAHuman
// (forsgren#61): both caller files exist next to the config, the pull
// request moves only forsgren.yml, and the reason names the one it leaves.
func TestCheckUpdateLeavesAPullRequestThatMovesOnlyOneOfTwoCallersForAHuman(t *testing.T) {
	recordedAPI(t, mergeableAnswers(t))
	flags := updateFlags(t)
	workflows := filepath.Join(filepath.Dir(flags["config"]), ".github", "workflows")
	if err := os.MkdirAll(workflows, 0o750); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"forsgren.yml", "forsgren-update.yml"} {
		if err := os.WriteFile(filepath.Join(workflows, name), []byte("name: caller\n"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	got := checkUpdateRun(argsOf(flags, "config", "repo", "pull")...)
	wantLeft(t, got,
		"moves .github/workflows/forsgren.yml but not .github/workflows/forsgren-update.yml")
}
