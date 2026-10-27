package github

import (
	"context"
	"net/http"
	"testing"
)

// The account type of the opener of one pull request (forsgren#500): GET
// /repos/{owner}/{repo}/pulls/{number}, user.type as ClosedPullRequests reads it.

const onePullPath = "/repos/acme/app/pulls/45"

// openerType asks the fake for the opener type of pull request 45.
func openerType(t *testing.T, f *fakeGitHub) (string, error) {
	t.Helper()
	return f.client(t, DefaultMaxPages).PullRequestUserType(context.Background(), "acme/app", 45)
}

// wantOpenerType fails unless the fake, answering body, gives type want with
// one GET of the pull request.
func wantOpenerType(t *testing.T, body, want string) {
	t.Helper()
	f := newFake(t)
	f.on(onePullPath, reply{body: body})
	got, err := openerType(t, f)
	if err != nil || got != want {
		t.Errorf("want type %q, got %q, %v", want, got, err)
	}
	if seen := f.seen(); len(seen) != 1 || seen[0].Method != http.MethodGet || seen[0].URL.Path != onePullPath {
		t.Errorf("want one GET of %s, got %v", onePullPath, seen)
	}
}

// TestPullRequestUserTypeReadsTheOpenersAccountType: the type as GitHub
// gives it, empty for a null user or none, and one GET of the pull request.
func TestPullRequestUserTypeReadsTheOpenersAccountType(t *testing.T) {
	for name, c := range map[string]struct{ body, want string }{
		"a person":        {`{"number": 45, "user": {"login": "acme-dev", "type": "User"}}`, "User"},
		"a bot":           {`{"number": 45, "user": {"login": "dependabot[bot]", "type": "Bot"}}`, "Bot"},
		"an organization": {`{"number": 45, "user": {"login": "acme", "type": "Organization"}}`, "Organization"},
		"no type":         {`{"number": 45, "user": {"login": "acme-dev"}}`, ""},
		"a null user":     {`{"number": 45, "user": null}`, ""},
	} {
		t.Run(name, func(t *testing.T) {
			wantOpenerType(t, c.body, c.want)
		})
	}
}

// TestPullRequestUserTypeOfAMissingPullRequestIsGone: a 404 or a 410 is
// ErrPullRequestGone, naming the repository and the number.
func TestPullRequestUserTypeOfAMissingPullRequestIsGone(t *testing.T) {
	for _, code := range []int{http.StatusNotFound, http.StatusGone} {
		f := newFake(t)
		f.on(onePullPath, reply{status: code, body: `{"message":"Not Found"}`})
		_, err := openerType(t, f)
		wantError(t, err, ErrPullRequestGone, "acme/app", "45")
	}
}

// TestPullRequestUserTypeOfARefusedReadNamesThePermission: a 403 is
// ErrAccess and ErrPullRequestsDenied, as the other pull request reads.
func TestPullRequestUserTypeOfARefusedReadNamesThePermission(t *testing.T) {
	f := newFake(t)
	f.on(onePullPath, reply{status: http.StatusForbidden, body: `{"message":"Resource not accessible"}`})
	_, err := openerType(t, f)
	wantError(t, err, ErrAccess, "Pull requests")
	wantError(t, err, ErrPullRequestsDenied)
}

// TestPullRequestUserTypeOfAnUnreadableAnswerIsAnswerError: a body that is no
// JSON object is ErrAnswer.
func TestPullRequestUserTypeOfAnUnreadableAnswerIsAnswerError(t *testing.T) {
	f := newFake(t)
	f.on(onePullPath, reply{body: `[]`})
	_, err := openerType(t, f)
	wantError(t, err, ErrAnswer, "acme/app")
}

// TestPullRequestUserTypeOfAnInvalidRepositoryNameSendsNoRequest: a name that
// is no owner/name is ErrRepositoryName.
func TestPullRequestUserTypeOfAnInvalidRepositoryNameSendsNoRequest(t *testing.T) {
	f := newFake(t)
	_, err := f.client(t, DefaultMaxPages).PullRequestUserType(context.Background(), "acme", 45)
	wantError(t, err, ErrRepositoryName)
	if n := len(f.seen()); n != 0 {
		t.Errorf("want no request, got %d", n)
	}
}
