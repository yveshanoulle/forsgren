package github

import (
	"context"
	"encoding/json"
	"fmt"
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

// Deployments lists the deployments of repo to environment created at or
// after since, newest first, and says whether it stopped at the page limit.
func (c *Client) Deployments(ctx context.Context, repo, environment string, since time.Time) (
	[]Deployment, bool, error,
) {
	created := func(d Deployment) time.Time { return d.CreatedAt }
	return listSince(ctx, c, repo, url.Values{"environment": {environment}}, since, created, "deployments")
}

// DeploymentStatuses lists every status of one deployment. A list longer
// than the page limit is an error: an outcome is never judged on part of it.
func (c *Client) DeploymentStatuses(ctx context.Context, repo string, id int64) ([]DeploymentStatus, error) {
	created := func(s DeploymentStatus) time.Time { return s.CreatedAt }
	statuses, truncated, err := listSince(ctx, c, repo, url.Values{}, time.Time{}, created,
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
	u, err := c.endpoint(repo, nil)
	if err != nil {
		return "", err
	}
	body, _, err := c.get(ctx, repo, u, jsonMedia)
	if err != nil {
		return "", err
	}
	var r struct {
		DefaultBranch string `json:"default_branch"`
	}
	if err := json.Unmarshal(body, &r); err != nil {
		return "", fmt.Errorf("%s: %w for %s: %w", repo, ErrAnswer, u.EscapedPath(), err)
	}
	if r.DefaultBranch == "" {
		return "", fmt.Errorf("%s: %w for %s: no default_branch", repo, ErrAnswer, u.EscapedPath())
	}
	return r.DefaultBranch, nil
}

// Runs lists the runs of one workflow file on branch created at or after
// since, newest first, and says whether it stopped at the page limit.
// GitHub is asked for runs created from the day before since, so no time
// zone of its date filter loses one; the exact cut is made here.
func (c *Client) Runs(ctx context.Context, repo, workflow, branch string, since time.Time) ([]Run, bool, error) {
	query := url.Values{
		"branch":  {branch},
		"created": {">=" + since.UTC().AddDate(0, 0, -1).Format(time.DateOnly)},
	}
	u, err := c.endpoint(repo, query, "actions", "workflows", workflow, "runs")
	if err != nil {
		return nil, false, err
	}
	var runs []Run
	created := func(r Run) time.Time { return r.CreatedAt }
	truncated, err := c.list(ctx, repo, u, func(body []byte) (bool, error) {
		var page struct {
			WorkflowRuns []Run `json:"workflow_runs"`
		}
		if err := json.Unmarshal(body, &page); err != nil {
			return false, err
		}
		return keep(&runs, page.WorkflowRuns, since, created), nil
	})
	if err != nil {
		return nil, false, err
	}
	return runs, truncated, nil
}

// Releases lists the releases published at or after since, newest first,
// drafts included (they have no publication time), and says whether it
// stopped at the page limit.
func (c *Client) Releases(ctx context.Context, repo string, since time.Time) ([]Release, bool, error) {
	published := func(r Release) time.Time { return r.PublishedAt }
	return listSince(ctx, c, repo, url.Values{}, since, published, "releases")
}

// TagCommit is the SHA of the commit tag points to, an annotated tag
// resolved to its commit: GET /repos/{owner}/{repo}/commits/tags/{tag} with
// the sha media type, which answers the SHA alone, as plain text.
func (c *Client) TagCommit(ctx context.Context, repo, tag string) (string, error) {
	u, err := c.endpoint(repo, nil, append([]string{"commits", "tags"}, strings.Split(tag, "/")...)...)
	if err != nil {
		return "", err
	}
	body, _, err := c.get(ctx, repo, u, "application/vnd.github.sha")
	if err != nil {
		return "", err
	}
	sha := strings.TrimSpace(string(body))
	if !isSHA(sha) {
		return "", fmt.Errorf("%s: %w for tag %s: not a commit SHA", repo, ErrAnswer, tag)
	}
	return sha, nil
}

// listSince reads a list of items at or after since (by at) under the
// repository's path segments.
func listSince[T any](ctx context.Context, c *Client, repo string, query url.Values, since time.Time,
	at func(T) time.Time, segments ...string,
) ([]T, bool, error) {
	u, err := c.endpoint(repo, query, segments...)
	if err != nil {
		return nil, false, err
	}
	var items []T
	truncated, err := c.list(ctx, repo, u, func(body []byte) (bool, error) {
		var page []T
		if err := json.Unmarshal(body, &page); err != nil {
			return false, err
		}
		return keep(&items, page, since, at), nil
	})
	if err != nil {
		return nil, false, err
	}
	return items, truncated, nil
}

// keep adds the items of one newest-first page at or after since to items,
// and an item without a time (a draft release) too. It says whether the next
// page may still hold such items: not when this one was empty or reached an
// item older than since.
func keep[T any](items *[]T, page []T, since time.Time, at func(T) time.Time) bool {
	more := len(page) > 0
	for _, item := range page {
		if t := at(item); !t.IsZero() && t.Before(since) {
			more = false
			continue
		}
		*items = append(*items, item)
	}
	return more
}

// isSHA says whether s is a git object name in lower-case hex.
func isSHA(s string) bool {
	return (len(s) == 40 || len(s) == 64) && strings.Trim(s, "0123456789abcdef") == ""
}
