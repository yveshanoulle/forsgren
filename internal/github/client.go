// Package github is forsgren's small client of GitHub's REST API: the few
// read-only calls `forsgren collect` needs (forsgren#12, step 5), with the
// standard library only.
//
// It sends the installation's token as a Bearer header and nowhere else: the
// token is never part of a URL, an error or a log line. Every error names the
// repository it was about.
package github

import (
	"context"
	"errors"
	"net/url"
	"time"
)

// DefaultMaxPages is how many pages of 100 one list reads at most: the
// newest 1000 deployments, runs or releases of a repository.
const DefaultMaxPages = 10

// The refusals; every error the client returns wraps one of them, except a
// failure to reach GitHub at all, which wraps the transport's own error.
var (
	ErrBaseURL        = errors.New("not an http or https API URL")
	ErrRepositoryName = errors.New("not an owner/name repository")
	ErrAccess         = errors.New("no access")
	ErrRateLimit      = errors.New("GitHub's rate limit is reached")
	ErrStatus         = errors.New("GitHub answered with an error")
	ErrAnswer         = errors.New("cannot read GitHub's answer")
	ErrForeignLink    = errors.New("the next page is not on the API host")
	ErrTooManyPages   = errors.New("more pages than forsgren reads")
)

// Client reads GitHub's REST API at one base URL with one token.
type Client struct {
	base     *url.URL
	token    string
	maxPages int
}

// New is a client of the API at baseURL (https://api.github.com, or a test
// server) that reads at most maxPages pages per list.
func New(baseURL, token string, maxPages int) (*Client, error) {
	u, err := url.Parse(baseURL)
	if err != nil {
		return nil, err
	}
	return &Client{base: u, token: token, maxPages: maxPages}, nil
}

// MaxPages is how many pages one list reads at most.
func (c *Client) MaxPages() int { return 0 }

// Deployment is one GitHub Deployment.
type Deployment struct {
	ID        int64     `json:"id"`
	SHA       string    `json:"sha"`
	Task      string    `json:"task"`
	CreatedAt time.Time `json:"created_at"`
}

// DeploymentStatus is one status of a GitHub Deployment.
type DeploymentStatus struct {
	ID        int64     `json:"id"`
	State     string    `json:"state"`
	CreatedAt time.Time `json:"created_at"`
}

// Run is one workflow run.
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

// Release is one GitHub Release.
type Release struct {
	ID          int64     `json:"id"`
	TagName     string    `json:"tag_name"`
	Draft       bool      `json:"draft"`
	Prerelease  bool      `json:"prerelease"`
	PublishedAt time.Time `json:"published_at"`
}

// Deployments lists the deployments of repo to environment created at or
// after since, and says whether it stopped at the page limit.
func (c *Client) Deployments(ctx context.Context, repo, environment string, since time.Time) (
	[]Deployment, bool, error,
) {
	return nil, false, nil
}

// DeploymentStatuses lists every status of one deployment.
func (c *Client) DeploymentStatuses(ctx context.Context, repo string, id int64) ([]DeploymentStatus, error) {
	return nil, nil
}

// DefaultBranch is the repository's default branch.
func (c *Client) DefaultBranch(ctx context.Context, repo string) (string, error) {
	return "", nil
}

// Runs lists the runs of one workflow file on branch created at or after
// since, and says whether it stopped at the page limit.
func (c *Client) Runs(ctx context.Context, repo, workflow, branch string, since time.Time) ([]Run, bool, error) {
	return nil, false, nil
}

// Releases lists the releases published at or after since (drafts too, which
// have no publication time), and says whether it stopped at the page limit.
func (c *Client) Releases(ctx context.Context, repo string, since time.Time) ([]Release, bool, error) {
	return nil, false, nil
}

// TagCommit is the SHA of the commit the tag points to.
func (c *Client) TagCommit(ctx context.Context, repo, tag string) (string, error) {
	return "", nil
}
