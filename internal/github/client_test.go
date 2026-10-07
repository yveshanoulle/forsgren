package github

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"testing"
	"time"
)

// page2 is a second page of deployments: one more, older than the fixture's.
const page2 = `[{"id": 1000, "sha": "9999999999999999999999999999999999999999", "task": "deploy",
  "environment": "production", "created_at": "2026-08-15T06:00:00Z"}]`

// wantError fails unless err wraps target and its message holds each of
// parts.
func wantError(t *testing.T, err, target error, parts ...string) {
	t.Helper()
	if !errors.Is(err, target) {
		t.Fatalf("want an error wrapping %q, got %v", target, err)
	}
	for _, part := range parts {
		if !strings.Contains(err.Error(), part) {
			t.Errorf("want %q in the error %q", part, err.Error())
		}
	}
}

// deploymentIDs lists the production deployments of acme/app from since and
// returns their IDs.
func deploymentIDs(t *testing.T, c *Client, from time.Time) ([]int64, bool) {
	t.Helper()
	got, truncated, err := c.Deployments(context.Background(), "acme/app", "production", Span{Since: from})
	if err != nil {
		t.Fatalf("want the deployments, got %v", err)
	}
	ids := make([]int64, 0, len(got))
	for _, d := range got {
		ids = append(ids, d.ID)
	}
	return ids, truncated
}

func wantIDs(t *testing.T, got []int64, want ...int64) {
	t.Helper()
	if len(got) != len(want) {
		t.Fatalf("want IDs %v, got %v", want, got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("want IDs %v, got %v", want, got)
		}
	}
}

// TestPaginationFollowsTheLinkNext: page 2 is read from the Link header's
// rel="next", with the same token.
func TestPaginationFollowsTheLinkNext(t *testing.T) {
	f := newFake(t)
	f.on(deploymentsPath, reply{header: next(deploymentsPath, "2"), body: fixture(t, "deployments.json")})
	f.onPage(deploymentsPath, "2", reply{body: page2})
	ids, truncated := deploymentIDs(t, f.client(t, DefaultMaxPages), since)
	wantIDs(t, ids, 1003, 1002, 1001, 1000)
	if truncated {
		t.Error("want all pages read, got truncated")
	}
	seen := f.seen()
	if len(seen) != 2 || seen[1].URL.Query().Get("page") != "2" {
		t.Fatalf("want page 1 then page 2, got %d requests", len(seen))
	}
}

// TestTheTokenIsSentAsABearerHeaderOnEveryRequest, page 2 included, with
// GitHub's media type, API version and a user agent.
func TestTheTokenIsSentAsABearerHeaderOnEveryRequest(t *testing.T) {
	f := newFake(t)
	f.on(deploymentsPath, reply{header: next(deploymentsPath, "2"), body: fixture(t, "deployments.json")})
	f.onPage(deploymentsPath, "2", reply{body: page2})
	deploymentIDs(t, f.client(t, DefaultMaxPages), since)
	want := map[string]string{
		"Authorization":        "Bearer " + token,
		"Accept":               "application/vnd.github+json",
		"X-Github-Api-Version": "2022-11-28",
		"User-Agent":           "forsgren",
	}
	seen := f.seen()
	if len(seen) != 2 {
		t.Fatalf("want 2 requests, got %d", len(seen))
	}
	for i, r := range seen {
		for name, value := range want {
			if got := r.Header.Get(name); got != value {
				t.Errorf("request %d: want %s %q, got %q", i+1, name, value, got)
			}
		}
		if strings.Contains(r.URL.String(), token) {
			t.Errorf("request %d: the token is in the URL %s", i+1, r.URL)
		}
	}
}

// TestListingStopsAfterThePageThatReachesSince: the lists are newest first,
// so a page with an item older than since is the last one read, and the
// older items are dropped.
func TestListingStopsAfterThePageThatReachesSince(t *testing.T) {
	f := newFake(t)
	f.on(deploymentsPath, reply{header: next(deploymentsPath, "2"), body: fixture(t, "deployments.json")})
	ids, truncated := deploymentIDs(t, f.client(t, DefaultMaxPages), time.Date(2026, 9, 5, 0, 0, 0, 0, time.UTC))
	wantIDs(t, ids, 1003, 1002)
	if n := len(f.seen()); n != 1 || truncated {
		t.Errorf("want page 1 only, not truncated, got %d requests, truncated=%v", n, truncated)
	}
}

// TestListingStopsAtThePageLimit: the first-run cap; the caller is told that
// older pages were left.
func TestListingStopsAtThePageLimit(t *testing.T) {
	f := newFake(t)
	f.on(deploymentsPath, reply{header: next(deploymentsPath, "2"), body: fixture(t, "deployments.json")})
	ids, truncated := deploymentIDs(t, f.client(t, 1), since)
	wantIDs(t, ids, 1003, 1002, 1001)
	if n := len(f.seen()); n != 1 || !truncated {
		t.Errorf("want page 1 only and truncated, got %d requests, truncated=%v", n, truncated)
	}
}

// TestStatusesBeyondThePageLimitAreAnError: a deployment's outcome needs all
// its statuses, so a cut list is refused rather than judged.
func TestStatusesBeyondThePageLimitAreAnError(t *testing.T) {
	f := newFake(t)
	f.on(statusesPath, reply{header: next(statusesPath, "2"), body: fixture(t, "deployment-statuses.json")})
	_, err := f.client(t, 1).DeploymentStatuses(context.Background(), "acme/app", 1003)
	wantError(t, err, ErrTooManyPages, "acme/app", "deployment 1003")
}

// TestALinkElsewhereIsNotFollowed: the token goes to the API host only. A
// next-page link to another host, or to the API's host over another scheme
// (https when the API is http, or the other way), is refused unread.
func TestALinkElsewhereIsNotFollowed(t *testing.T) {
	for name, base := range map[string]func(*fakeGitHub) string{
		"another host":   func(*fakeGitHub) string { return "http://elsewhere.invalid" },
		"another scheme": func(f *fakeGitHub) string { return strings.Replace(f.srv.URL, "http://", "https://", 1) },
	} {
		t.Run(name, func(t *testing.T) {
			f := newFake(t)
			link := http.Header{"Link": {`<` + base(f) + deploymentsPath + `?page=2>; rel="next"`}}
			f.on(deploymentsPath, reply{header: link, body: fixture(t, "deployments.json")})
			_, _, err := f.client(t, DefaultMaxPages).Deployments(context.Background(), "acme/app", "production", sinceOnly)
			wantError(t, err, ErrForeignLink, "acme/app")
			if n := len(f.seen()); n != 1 {
				t.Errorf("want 1 request, got %d", n)
			}
		})
	}
}

// TestHTTPErrorsNameTheRepository: 401, 403 and 404 say to check the token's
// access to the repository; a rate limit says when it resets; any other
// error status names the repository too.
func TestHTTPErrorsNameTheRepository(t *testing.T) {
	access := "check FORSGREN_TOKEN's access to acme/app"
	limited := http.Header{"X-Ratelimit-Remaining": {"0"}, "X-Ratelimit-Reset": {"1790000000"}}
	for name, c := range map[string]struct {
		reply  reply
		target error
		parts  []string
	}{
		"401": {reply{status: 401}, ErrAccess, []string{"401 Unauthorized", access}},
		"403": {reply{status: 403}, ErrAccess, []string{"403 Forbidden", access}},
		"404": {reply{status: 404}, ErrAccess, []string{"404 Not Found", deploymentsPath, access}},
		"rate limit": {reply{status: 403, header: limited}, ErrRateLimit,
			[]string{"resets at 2026-09-21T14:13:20Z"}},
		"secondary rate limit": {reply{status: 429, header: http.Header{"Retry-After": {"60"}}}, ErrRateLimit,
			[]string{"retry after 60 seconds"}},
		"rate limit, no time": {reply{status: 429, header: http.Header{"Retry-After": {"soon " + token}}},
			ErrRateLimit, []string{"rate limit is reached"}},
		"server error": {reply{status: 502}, ErrStatus, []string{"502 Bad Gateway", deploymentsPath}},
	} {
		t.Run(name, func(t *testing.T) {
			f := newFake(t)
			f.on(deploymentsPath, c.reply)
			_, _, err := f.client(t, DefaultMaxPages).Deployments(context.Background(), "acme/app", "production", sinceOnly)
			wantError(t, err, c.target, append([]string{"acme/app: "}, c.parts...)...)
			if strings.Contains(err.Error(), token) {
				t.Errorf("the token is in the error %q", err)
			}
		})
	}
}

// TestARefusalNamesTheTokenTheClientWasBuiltFrom (forsgren#73): a client of
// the workflow job's token tells a refused caller to check GITHUB_TOKEN, not
// FORSGREN_TOKEN, which it never read.
func TestARefusalNamesTheTokenTheClientWasBuiltFrom(t *testing.T) {
	f := newFake(t)
	f.on(deploymentsPath, reply{status: 403})
	client := f.client(t, DefaultMaxPages).WithTokenName("GITHUB_TOKEN")
	_, _, err := client.Deployments(context.Background(), "acme/app", "production", sinceOnly)
	wantError(t, err, ErrAccess, "check GITHUB_TOKEN's access to acme/app")
}

// TestMalformedJSONNamesTheRepository, for each call that reads JSON.
func TestMalformedJSONNamesTheRepository(t *testing.T) {
	for name, call := range calls("acme/app") {
		if name == "tag commit" {
			continue // plain text, see TestTagCommitRefusesAnAnswerThatIsNotASHA
		}
		t.Run(name, func(t *testing.T) {
			f := newFake(t)
			paths := []string{deploymentsPath, statusesPath, "/repos/acme/app", runsPath, releasesPath, comparePath,
				issuesPath, "/repos/acme/app/releases/latest",
				"/repos/acme/app/pulls"}
			for _, path := range paths {
				f.on(path, reply{body: `[{"id": "not a number"`})
			}
			wantError(t, call(f.client(t, DefaultMaxPages)), ErrAnswer, "acme/app: ")
		})
	}
}

// TestEveryCallPassesGitHubsRefusalOn: no call takes a 404 for an empty
// answer. Every call but the tag's and the comparison's says to check the
// token's access; a 404 there is the tag missing
// (TestAMissingTagIsNamedNotTheToken) or a commit missing
// (TestCompareNamesAMissingCommitNotTheToken).
func TestEveryCallPassesGitHubsRefusalOn(t *testing.T) {
	missingNotAccess := map[string]bool{"tag commit": true, "compare": true}
	for name, call := range calls("acme/app") {
		t.Run(name, func(t *testing.T) {
			f := newFake(t)
			err := call(f.client(t, DefaultMaxPages))
			if missingNotAccess[name] {
				if err == nil || !strings.HasPrefix(err.Error(), "acme/app: ") {
					t.Errorf("want an error that names acme/app, got %v", err)
				}
				return
			}
			wantError(t, err, ErrAccess, "check FORSGREN_TOKEN's access to acme/app")
		})
	}
}

// TestACutAnswerNamesTheRepository: an answer shorter than it said it
// would be is an error, not a short list.
func TestACutAnswerNamesTheRepository(t *testing.T) {
	f := newFake(t)
	f.on(deploymentsPath, reply{header: http.Header{"Content-Length": {"5000"}}, body: `[]`})
	_, _, err := f.client(t, DefaultMaxPages).Deployments(context.Background(), "acme/app", "production", sinceOnly)
	wantError(t, err, ErrAnswer, "acme/app: ", deploymentsPath, "unexpected EOF")
}

// TestTheTokenIsNeverInAnError, even when GitHub's answer echoes it.
func TestTheTokenIsNeverInAnError(t *testing.T) {
	echo := http.Header{"X-Echo": {token}}
	for name, r := range map[string]reply{
		"401":       {status: 401, header: echo, body: `{"message":"Bad credentials ` + token + `"}`},
		"500":       {status: 500, header: echo, body: token},
		"malformed": {header: echo, body: `[{"task": "` + token + `", "id": "x"}]`},
	} {
		t.Run(name, func(t *testing.T) {
			f := newFake(t)
			f.on(deploymentsPath, r)
			_, _, err := f.client(t, DefaultMaxPages).Deployments(context.Background(), "acme/app", "production", sinceOnly)
			if err == nil || strings.Contains(err.Error(), token) {
				t.Errorf("want an error without the token, got %v", err)
			}
		})
	}
}

// TestAnUnreachableGitHubNamesTheRepositoryNotTheToken.
func TestAnUnreachableGitHubNamesTheRepositoryNotTheToken(t *testing.T) {
	f := newFake(t)
	c := f.client(t, DefaultMaxPages)
	f.srv.Close()
	_, _, err := c.Deployments(context.Background(), "acme/app", "production", sinceOnly)
	if err == nil || !strings.HasPrefix(err.Error(), "acme/app: ") || strings.Contains(err.Error(), token) {
		t.Errorf("want an error that names acme/app and not the token, got %v", err)
	}
}

// TestRepositoryNamesAreCheckedBeforeAnyRequest: a name that is not one
// owner/name never becomes a URL, in any call.
func TestRepositoryNamesAreCheckedBeforeAnyRequest(t *testing.T) {
	for _, repo := range []string{
		"", "acme", "acme/", "/app", "acme/app/x", "acme/.", "acme/..", "acme/app?x=1", "ac me/app",
	} {
		f := newFake(t)
		c := f.client(t, DefaultMaxPages)
		for name, call := range calls(repo) {
			if err := call(c); !errors.Is(err, ErrRepositoryName) {
				t.Errorf("%s of %q: want ErrRepositoryName, got %v", name, repo, err)
			}
		}
		if n := len(f.seen()); n != 0 {
			t.Errorf("%q: want no request, got %d", repo, n)
		}
	}
}

// TestThePageLimitIsAtLeastOne: a list always reads its first page.
func TestThePageLimitIsAtLeastOne(t *testing.T) {
	for limit, want := range map[int]int{-1: 1, 0: 1, 1: 1, 25: 25} {
		c, err := New("https://api.github.com", token, limit)
		if err != nil || c.MaxPages() != want {
			t.Errorf("New with %d pages: want a limit of %d, got %v, %v", limit, want, c, err)
		}
	}
}

// TestNewRefusesABaseURLThatIsNotHTTP.
func TestNewRefusesABaseURLThatIsNotHTTP(t *testing.T) {
	for _, base := range []string{"", "api.github.com", "ftp://api.github.com", "https://", "http://[::1"} {
		if _, err := New(base, token, DefaultMaxPages); !errors.Is(err, ErrBaseURL) {
			t.Errorf("%q: want ErrBaseURL, got %v", base, err)
		}
	}
}
