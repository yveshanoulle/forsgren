package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// TestRenderRefusesAWaitingPRThatIsNoPullRequest (forsgren#41, review of
// step 7): a pull request's number is 1 or more, so --waiting-pr 0 or below
// is a usage error that names the flag, as run-summary's flags are; leaving
// the flag out is how render is told there is none.
func TestRenderRefusesAWaitingPRThatIsNoPullRequest(t *testing.T) {
	for _, number := range []string{"0", "-3"} {
		code, stderr, _ := renderWith(t, "--latest", "0.6.1", "--waiting-pr", number)
		if code != 2 || !strings.Contains(stderr, "--waiting-pr") {
			t.Errorf("--waiting-pr %s: want exit 2 naming --waiting-pr, got %d, %q", number, code, stderr)
		}
	}
}

// TestRenderTimeIsNeverBeforeTheEpoch (forsgren#41, review of step 7): the
// reproducible-builds variable is a non-negative number of seconds; 0 is
// the first minute of 1970, and a negative value fails the render, naming
// the variable.
func TestRenderTimeIsNeverBeforeTheEpoch(t *testing.T) {
	t.Setenv(sourceDateEpoch, "0")
	if _, _, index := renderWith(t); !strings.Contains(index, "Calculated at 1970-01-01 00:00 UTC</p>") {
		t.Errorf("want 1970-01-01 00:00 UTC in the footer, got:\n%s", index)
	}
	t.Setenv(sourceDateEpoch, "-1")
	if code, stderr, _ := renderWith(t); code != 1 || !strings.Contains(stderr, sourceDateEpoch) {
		t.Errorf("want exit 1 naming %s, got %d, %q", sourceDateEpoch, code, stderr)
	}
}

// answerAPI points the commands at a test server that gives every request
// the status code and the headers, and returns the Authorization header of
// the last request it saw.
func answerAPI(t *testing.T, code int, header http.Header, body string) *string {
	t.Helper()
	seen := new(string)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		*seen = r.Header.Get("Authorization")
		for name, values := range header {
			w.Header()[name] = values
		}
		w.WriteHeader(code)
		_, _ = w.Write([]byte(body))
	}))
	t.Cleanup(srv.Close)
	old := githubAPI
	githubAPI = srv.URL
	t.Cleanup(func() { githubAPI = old })
	return seen
}

// TestLatestReleaseSendsTheJobTokenOnlyWhenThereIsOne (forsgren#40, review
// of step 7): latest-release reads with GITHUB_TOKEN, the job's token, as a
// Bearer header, and with no Authorization header at all without one (an
// empty Bearer is refused by GitHub, where no header reads a public
// repository).
func TestLatestReleaseSendsTheJobTokenOnlyWhenThereIsOne(t *testing.T) {
	for token, want := range map[string]string{"": "", "job-token": "Bearer job-token"} {
		t.Setenv("GITHUB_TOKEN", token)
		t.Setenv("FORSGREN_TOKEN", "caller-secret")
		seen := answerAPI(t, http.StatusOK, nil, `{"id": 7, "tag_name": "v0.0.10"}`)
		wantLookup(t, "0.0.10\n", "", "latest-release")
		if *seen != want {
			t.Errorf("GITHUB_TOKEN %q: want Authorization %q, got %q", token, want, *seen)
		}
	}
}

// TestARateLimitedLookupIsNotAMissingPermission (forsgren#40, review of step
// 7): a 403 that is GitHub's rate limit (X-RateLimit-Remaining: 0) is not a
// token without pull-requests: read: the lookup says rate limit on stderr
// and writes the status rate-limited, so the run summary never asks for a
// permission the caller already grants. A plain 403 stays no-access.
func TestARateLimitedLookupIsNotAMissingPermission(t *testing.T) {
	t.Setenv("GITHUB_REPOSITORY", "acme/data")
	noneLeft := http.Header{"X-Ratelimit-Remaining": {"0"}}
	answerAPI(t, http.StatusForbidden, noneLeft, `{"message":"API rate limit exceeded"}`)
	wantStatus(t, "rate-limited")
	wantLookup(t, "", "rate limit", "waiting-pull-request", "--version", "0.0.10")
	answerAPI(t, http.StatusForbidden, nil, `{"message":"Resource not accessible by integration"}`)
	wantStatus(t, "no-access")
}
