package github

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// Deployment is one GitHub Deployment (GET /repos/{owner}/{repo}/deployments).
type Deployment struct {
	ID        int64     `json:"id"`
	SHA       string    `json:"sha"`
	Task      string    `json:"task"`
	CreatedAt time.Time `json:"created_at"`
}

// DeploymentStatus is one status of a GitHub Deployment. State is error,
// failure, inactive, in_progress, queued, pending or success.
type DeploymentStatus struct {
	ID        int64     `json:"id"`
	State     string    `json:"state"`
	CreatedAt time.Time `json:"created_at"`
}

// Run is one workflow run. Conclusion is empty (null) until Status is
// completed.
type Run struct {
	ID             int64     `json:"id"`
	HeadSHA        string    `json:"head_sha"`
	HeadBranch     string    `json:"head_branch"`
	Status         string    `json:"status"`
	Conclusion     string    `json:"conclusion"`
	CreatedAt      time.Time `json:"created_at"`
	RunStartedAt   time.Time `json:"run_started_at"`
	HeadRepository struct {
		FullName string `json:"full_name"`
	} `json:"head_repository"`
}

// Release is one GitHub Release. PublishedAt is zero (null) for a draft.
type Release struct {
	ID          int64     `json:"id"`
	TagName     string    `json:"tag_name"`
	Draft       bool      `json:"draft"`
	Prerelease  bool      `json:"prerelease"`
	PublishedAt time.Time `json:"published_at"`
}

// Span is the part of a newest-first list a read keeps: the items created at
// or after Since and before Until; no Until (the zero time) reaches to the
// newest item (forsgren#57).
type Span struct {
	Since, Until time.Time
}

// Deployments lists the deployments of repo to environment created in span,
// newest first, and says whether it stopped at the page limit. GitHub lists
// them with no date filter, so a span with an Until still pages from the
// newest, and keeps only what is in it.
func (c *Client) Deployments(ctx context.Context, repo, environment string, span Span) (
	[]Deployment, bool, error,
) {
	created := func(d Deployment) time.Time { return d.CreatedAt }
	return listSince(ctx, c, repo, url.Values{"environment": {environment}}, span, created, "deployments")
}

// DeploymentStatuses lists every status of one deployment. A list longer
// than the page limit is an error: an outcome is never judged on part of it.
func (c *Client) DeploymentStatuses(ctx context.Context, repo string, id int64) ([]DeploymentStatus, error) {
	created := func(s DeploymentStatus) time.Time { return s.CreatedAt }
	statuses, truncated, err := listSince(ctx, c, repo, url.Values{}, Span{}, created,
		"deployments", strconv.FormatInt(id, 10), "statuses")
	if err == nil && truncated {
		err = fmt.Errorf("%s: deployment %d: %w: %d pages of statuses", repo, id, ErrTooManyPages, c.maxPages)
	}
	if err != nil {
		return nil, err
	}
	return statuses, nil
}

// DefaultBranch is the repository's default branch (GET
// /repos/{owner}/{repo}, default_branch).
func (c *Client) DefaultBranch(ctx context.Context, repo string) (string, error) {
	t, err := c.endpoint(repo, nil)
	if err != nil {
		return "", err
	}
	body, _, err := c.get(ctx, t, jsonMedia)
	if err != nil {
		return "", err
	}
	var r struct {
		DefaultBranch string `json:"default_branch"`
	}
	if err := json.Unmarshal(body, &r); err != nil {
		return "", fmt.Errorf("%s: %w for %s: %w", repo, ErrAnswer, t.path(), err)
	}
	if r.DefaultBranch == "" {
		return "", fmt.Errorf("%s: %w for %s: no default_branch", repo, ErrAnswer, t.path())
	}
	return r.DefaultBranch, nil
}

// Runs lists the runs of one workflow file on branch created in span, newest
// first, and says whether it stopped at the page limit. GitHub is asked for
// runs created from the day before Since, and to the day after Until when
// there is one (its created filter takes the range from..to), so no time
// zone of its date filter loses one; the exact cut is made here.
func (c *Client) Runs(ctx context.Context, repo, workflow, branch string, span Span) ([]Run, bool, error) {
	query := url.Values{"branch": {branch}, "created": {createdFilter(span)}}
	t, err := c.endpoint(repo, query, "actions", "workflows", workflow, "runs")
	if err != nil {
		return nil, false, err
	}
	var runs []Run
	created := func(r Run) time.Time { return r.CreatedAt }
	truncated, err := c.list(ctx, t, func(body []byte) (bool, error) {
		var page struct {
			WorkflowRuns []Run `json:"workflow_runs"`
		}
		if err := json.Unmarshal(body, &page); err != nil {
			return false, err
		}
		return keep(&runs, page.WorkflowRuns, span, created), nil
	})
	if err != nil {
		return nil, false, err
	}
	return runs, truncated, nil
}

// createdFilter is GitHub's created filter for span: from the day before
// Since, on to the day after Until when there is one.
func createdFilter(span Span) string {
	from := span.Since.UTC().AddDate(0, 0, -1).Format(time.DateOnly)
	if span.Until.IsZero() {
		return ">=" + from
	}
	return from + ".." + span.Until.UTC().AddDate(0, 0, 1).Format(time.DateOnly)
}

// Releases lists the releases published in span, newest first, drafts
// included (they have no publication time), and says whether it stopped at
// the page limit. Like deployments, an Until does not skip the newest pages.
func (c *Client) Releases(ctx context.Context, repo string, span Span) ([]Release, bool, error) {
	published := func(r Release) time.Time { return r.PublishedAt }
	return listSince(ctx, c, repo, url.Values{}, span, published, "releases")
}

// TagCommit is the SHA of the commit tag points to, an annotated tag
// resolved to its commit: GET /repos/{owner}/{repo}/commits/tags/{tag} with
// the sha media type, which answers the SHA alone, as plain text. A 404 or
// 422 is the tag missing (ErrMissingTag), not the token's access: the
// releases that name the tag were read with the same token.
func (c *Client) TagCommit(ctx context.Context, repo, tag string) (string, error) {
	t, err := c.endpoint(repo, nil, append([]string{"commits", "tags"}, strings.Split(tag, "/")...)...)
	if err != nil {
		return "", err
	}
	body, _, err := c.get(ctx, t, "application/vnd.github.sha")
	if missing, ok := errors.AsType[*answerError](err); ok && isMissingRef(missing.code) {
		return "", fmt.Errorf("%s: tag %s not found: %s for %s: %w; was it deleted after the release was published?",
			repo, tag, missing.status(), t.path(), ErrMissingTag)
	}
	if err != nil {
		return "", err
	}
	sha := strings.TrimSpace(string(body))
	if !isSHA(sha) {
		return "", fmt.Errorf("%s: %w for tag %s: not a commit SHA", repo, ErrAnswer, tag)
	}
	return sha, nil
}

// isMissingRef says whether code is GitHub's answer for a ref it does not
// have: 404, or 422 (No commit found for SHA).
func isMissingRef(code int) bool {
	return code == http.StatusNotFound || code == http.StatusUnprocessableEntity
}

// listSince reads a list of items at or after since (by at) under the
// repository's path segments.
func listSince[T any](ctx context.Context, c *Client, repo string, query url.Values, span Span,
	at func(T) time.Time, segments ...string,
) ([]T, bool, error) {
	t, err := c.endpoint(repo, query, segments...)
	if err != nil {
		return nil, false, err
	}
	var items []T
	truncated, err := c.list(ctx, t, func(body []byte) (bool, error) {
		var page []T
		if err := json.Unmarshal(body, &page); err != nil {
			return false, err
		}
		return keep(&items, page, span, at), nil
	})
	if err != nil {
		return nil, false, err
	}
	return items, truncated, nil
}

// keep adds the items of one newest-first page in span to items, and an item
// without a time (a draft release) too. It says whether the next page may
// still hold such items: not when this one was empty or reached an item older
// than Since. An item from Until on is passed over, and the next page is read.
func keep[T any](items *[]T, page []T, span Span, at func(T) time.Time) bool {
	more := len(page) > 0
	for _, item := range page {
		switch span.place(at(item)) {
		case tooOld:
			more = false
		case tooNew:
		default:
			*items = append(*items, item)
		}
	}
	return more
}

// Where an item stands to a Span.
const (
	inside = iota
	tooOld
	tooNew
)

// place says where t stands to span: an item without a time (a draft
// release) is inside.
func (span Span) place(t time.Time) int {
	switch {
	case t.IsZero():
		return inside
	case t.Before(span.Since):
		return tooOld
	case !span.Until.IsZero() && !t.Before(span.Until):
		return tooNew
	}
	return inside
}

// isSHA says whether s is a git object name in lower-case hex.
func isSHA(s string) bool {
	return (len(s) == 40 || len(s) == 64) && strings.Trim(s, "0123456789abcdef") == ""
}

// LatestRelease is the repository's latest published release (not a draft,
// not a prerelease): GET /repos/{owner}/{repo}/releases/latest. A repository
// with no release is GitHub's 404, which reaches the caller as an error.
func (c *Client) LatestRelease(ctx context.Context, repo string) (Release, error) {
	t, err := c.endpoint(repo, nil, "releases", "latest")
	if err != nil {
		return Release{}, err
	}
	body, _, err := c.get(ctx, t, jsonMedia)
	if err != nil {
		return Release{}, err
	}
	var r Release
	if err := json.Unmarshal(body, &r); err != nil {
		return Release{}, fmt.Errorf("%s: %w for %s: %w", repo, ErrAnswer, t.path(), err)
	}
	return r, nil
}
