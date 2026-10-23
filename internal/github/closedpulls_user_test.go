package github

import (
	"fmt"
	"slices"
	"strings"
	"testing"
)

// The author's account type of a closed pull request (forsgren#345, step 1).

// closedWithUser is pull request 45 as GitHub lists it, its user the JSON
// value user ("null" for none).
func closedWithUser(user string) string {
	return `{"number": 45, "user": ` + user + `, "created_at": "2026-07-01T08:00:00Z", ` +
		`"updated_at": "2026-08-02T09:00:00Z", "merged_at": "2026-08-02T08:00:00Z", "merge_commit_sha": "` +
		shaBase + `"}`
}

// userTypes is the user type of each of pulls, in order.
func userTypes(pulls []ClosedPullRequest) []string {
	out := make([]string, 0, len(pulls))
	for _, p := range pulls {
		out = append(out, p.UserType)
	}
	return out
}

// TestClosedPullRequestsReadTheAuthorsAccountType (forsgren#345): user.type
// as GitHub gives it, "Bot" for a bot account whatever its login, and empty
// when GitHub names no author (a null user) or no type, never a guess.
func TestClosedPullRequestsReadTheAuthorsAccountType(t *testing.T) {
	for name, c := range map[string]struct{ user, want string }{
		"a person":        {`{"login": "acme-dev", "type": "User"}`, "User"},
		"a bot":           {`{"login": "dependabot[bot]", "type": "Bot"}`, "Bot"},
		"a bot login":     {`{"login": "acme-helper", "type": "Bot"}`, "Bot"},
		"an organization": {`{"login": "acme", "type": "Organization"}`, "Organization"},
		"no type":         {`{"login": "acme-dev"}`, ""},
		"a null user":     {"null", ""},
	} {
		t.Run(name, func(t *testing.T) {
			f := newFake(t)
			f.on(closedPullsPath, reply{body: "[" + closedWithUser(c.user) + "]"})
			got, _, err := closedPulls(t, f, DefaultMaxPages)
			if !slices.Equal(userTypes(got), []string{c.want}) {
				t.Errorf("want one pull request of user type %q, got %+v, %v", c.want, got, err)
			}
		})
	}
}

// TestAClosedPullRequestHoldsNoLogin (forsgren#255, #345): the author's
// login is never read, so nothing collect can store holds it, whatever the
// account type.
func TestAClosedPullRequestHoldsNoLogin(t *testing.T) {
	f := newFake(t)
	f.on(closedPullsPath, reply{body: fixture(t, "closed-pulls.json")})
	got, _, err := closedPulls(t, f, DefaultMaxPages)
	if err != nil || len(got) != 2 {
		t.Fatalf("want the fixture's two pull requests, got %d, %v", len(got), err)
	}
	held := fmt.Sprintf("%+v", got)
	for _, login := range []string{"acme-dev", "dependabot"} {
		if strings.Contains(held, login) {
			t.Errorf("want no login %q held, got %s", login, held)
		}
	}
}
