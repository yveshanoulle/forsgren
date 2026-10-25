package github

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"time"
)

// ErrPushesDenied is the 403 of BranchActivities: the token cannot read the
// repository's activity list (Contents: read). It comes with ErrAccess,
// which it narrows.
var ErrPushesDenied = errors.New("pushes are not readable")

// The kinds of activity BranchActivities returns (GitHub's activity_type);
// the others (branch creation and deletion, merge queue merges) are left out.
const (
	ActivityPush      = "push"
	ActivityPRMerge   = "pr_merge"
	ActivityForcePush = "force_push"
)

// Activity is one push to a branch (forsgren#397, step 2): what time to main
// and batch size per push need. Nothing else is read: no login, only the
// actor's account type.
type Activity struct {
	// Kind is ActivityPush, ActivityPRMerge or ActivityForcePush.
	Kind     string
	PushedAt time.Time
	// Before and After are the branch's tip before and after the push.
	Before, After string
	// ActorType is GitHub's account type of the actor (actor.type: "User",
	// "Bot"), empty when GitHub names none.
	ActorType string
}

// activity is one item of GitHub's answer, the fields BranchActivities reads.
type activity struct {
	Timestamp time.Time `json:"timestamp"`
	Before    string    `json:"before"`
	After     string    `json:"after"`
	Kind      string    `json:"activity_type"`
	Actor     *struct {
		Type string `json:"type"`
	} `json:"actor"`
}

// BranchActivities lists the pushes, pull request merges and force pushes to
// branch of repo at or after since, newest first: GET
// /repos/{owner}/{repo}/activity?ref=refs/heads/{branch}, 100 per page, up to
// the page limit; it says whether it stopped there. The list has no since
// filter, so the read ends at the first activity before since, which is left
// out. A 403 is the token missing Contents: read, ErrAccess and
// ErrPushesDenied, unless it is GitHub's rate limit, which stays
// ErrRateLimit. A wanted activity with no time or a SHA that is none is
// ErrAnswer.
func (c *Client) BranchActivities(ctx context.Context, repo, branch string, since time.Time) (
	[]Activity, bool, error,
) {
	t, err := c.endpoint(repo, url.Values{"ref": {"refs/heads/" + branch}}, "activity")
	if err != nil {
		return nil, false, err
	}
	var all []Activity
	at := func(a Activity) time.Time { return a.PushedAt }
	truncated, err := c.list(ctx, t, func(body []byte) (bool, error) {
		page, err := readActivities(body)
		if err != nil {
			return false, err
		}
		return keep(&all, page, Span{Since: since}, at), nil
	})
	if err != nil {
		return nil, false, c.explainPushesDenied(repo, t, err)
	}
	return wantedActivities(all), truncated, nil
}

// explainPushesDenied is err, or, when err is the 403 of a token without
// Contents: read (not GitHub's rate limit), the error that says so, naming
// the token that was refused and its fix (forsgren#318).
func (c *Client) explainPushesDenied(repo string, t target, err error) error {
	return c.explainRefusal(repo, t, err, permission{"contents", "Contents", ErrPushesDenied})
}

// wantedActivities is the activities of the kinds forsgren stores.
func wantedActivities(all []Activity) []Activity {
	var out []Activity
	for _, a := range all {
		if isWantedKind(a.Kind) {
			out = append(out, a)
		}
	}
	return out
}

// isWantedKind says whether kind is one BranchActivities returns.
func isWantedKind(kind string) bool {
	return kind == ActivityPush || kind == ActivityPRMerge || kind == ActivityForcePush
}

// readActivities is the Activity of each item of one page, in UTC.
func readActivities(body []byte) ([]Activity, error) {
	var items []activity
	if err := json.Unmarshal(body, &items); err != nil {
		return nil, err
	}
	page := make([]Activity, 0, len(items))
	for _, item := range items {
		a, err := item.toActivity()
		if err != nil {
			return nil, err
		}
		page = append(page, a)
	}
	return page, nil
}

// toActivity is the Activity of one item; one of a wanted kind needs a time
// and two SHAs, any other is read as it is.
func (a activity) toActivity() (Activity, error) {
	out := Activity{Kind: a.Kind, PushedAt: a.Timestamp.UTC(), Before: a.Before, After: a.After}
	if a.Actor != nil {
		out.ActorType = a.Actor.Type
	}
	if isWantedKind(a.Kind) && !a.complete() {
		return Activity{}, fmt.Errorf("%s activity has no time or no SHA", a.Kind)
	}
	return out, nil
}

// complete says whether a has the time and the two SHAs a push needs.
func (a activity) complete() bool {
	return !a.Timestamp.IsZero() && isSHA(a.Before) && isSHA(a.After)
}
