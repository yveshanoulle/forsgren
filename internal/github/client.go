// Package github is forsgren's small client of GitHub's REST API: the few
// read-only calls `forsgren collect` needs (forsgren#12, step 5), with the
// standard library only.
//
// It sends the installation's token as a Bearer header and nowhere else: the
// token is never part of a URL, an error or a log line, and a next-page link
// to another host is refused rather than followed with it. Every error names
// the repository it was about.
package github

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// DefaultMaxPages is how many pages of 100 one list reads at most: the
// newest 1000 deployments, runs or releases of a repository.
const DefaultMaxPages = 10

const (
	perPage    = "100"
	apiVersion = "2022-11-28"
	jsonMedia  = "application/vnd.github+json"
	// maxBody bounds one answer; a page of 100 workflow runs is well under it.
	maxBody = 32 << 20
)

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
	http     *http.Client
}

// New is a client of the API at baseURL (https://api.github.com, or a test
// server) that reads at most maxPages pages per list, and at least one.
func New(baseURL, token string, maxPages int) (*Client, error) {
	u, err := url.Parse(baseURL)
	if err != nil || (u.Scheme != "https" && u.Scheme != "http") || u.Host == "" {
		return nil, fmt.Errorf("%w: %q", ErrBaseURL, baseURL)
	}
	u.Path = "/" + strings.TrimPrefix(u.Path, "/")
	return &Client{base: u, token: token, maxPages: max(maxPages, 1), http: &http.Client{Timeout: time.Minute}}, nil
}

// MaxPages is how many pages one list reads at most.
func (c *Client) MaxPages() int { return c.maxPages }

// repositoryName is GitHub's owner/name, as config checks it.
var repositoryName = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9._-]+$`)

// endpoint is the URL of a path under /repos/{owner}/{name}, with query and
// 100 per page; the repository name is checked first, so a name that is
// not one owner/name never becomes a URL.
func (c *Client) endpoint(repo string, query url.Values, segments ...string) (*url.URL, error) {
	if !repositoryName.MatchString(repo) || strings.HasSuffix(repo, "/.") || strings.HasSuffix(repo, "/..") {
		return nil, fmt.Errorf("%w: %q", ErrRepositoryName, repo)
	}
	owner, name, _ := strings.Cut(repo, "/")
	escaped := []string{"repos", owner, name}
	for _, s := range segments {
		escaped = append(escaped, url.PathEscape(s))
	}
	u := c.base.JoinPath(escaped...)
	if query != nil {
		query.Set("per_page", perPage)
		u.RawQuery = query.Encode()
	}
	return u, nil
}

// get fetches u with the token and the media type accept: the body of a 2xx
// answer and its headers, or an error that names repo.
func (c *Client) get(ctx context.Context, repo string, u *url.URL, accept string) ([]byte, http.Header, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
	if err != nil {
		return nil, nil, fmt.Errorf("%s: %w", repo, err)
	}
	req.Header.Set("Authorization", "Bearer "+c.token)
	req.Header.Set("Accept", accept)
	req.Header.Set("X-GitHub-Api-Version", apiVersion)
	req.Header.Set("User-Agent", "forsgren")
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, nil, fmt.Errorf("%s: cannot reach GitHub: %w", repo, err)
	}
	defer func() { _ = resp.Body.Close() }()
	if err := statusError(repo, u, resp); err != nil {
		return nil, nil, err
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxBody))
	if err != nil {
		return nil, nil, fmt.Errorf("%s: %w for %s: %w", repo, ErrAnswer, u.EscapedPath(), err)
	}
	return body, resp.Header, nil
}

// statusError is nil for a 2xx answer, else the error that says what to do.
// It never quotes the answer's body or headers: an answer can echo anything.
func statusError(repo string, u *url.URL, resp *http.Response) error {
	code := resp.StatusCode
	status := fmt.Sprintf("%d %s", code, http.StatusText(code))
	switch {
	case code >= 200 && code < 300:
		return nil
	case isRateLimited(resp):
		return rateLimitError(repo, resp.Header)
	case isRefused(code):
		return fmt.Errorf("%s: %w: %s for %s; check FORSGREN_TOKEN's access to %s",
			repo, ErrAccess, status, u.EscapedPath(), repo)
	default:
		return fmt.Errorf("%s: %w: %s for %s", repo, ErrStatus, status, u.EscapedPath())
	}
}

// isRefused says whether code is GitHub refusing the token: 401 (no valid
// token), 403 (not allowed) or 404, which is also how GitHub answers a
// private repository the token cannot see.
func isRefused(code int) bool {
	switch code {
	case http.StatusUnauthorized, http.StatusForbidden, http.StatusNotFound:
		return true
	}
	return false
}

// isRateLimited: GitHub answers 403 or 429 when a rate limit is reached,
// with no request left (the primary limit) or with a Retry-After (a
// secondary limit).
func isRateLimited(resp *http.Response) bool {
	if resp.StatusCode != http.StatusForbidden && resp.StatusCode != http.StatusTooManyRequests {
		return false
	}
	return resp.Header.Get("X-RateLimit-Remaining") == "0" || resp.Header.Get("Retry-After") != ""
}

// rateLimitError says when to try again: the reset time of the primary
// limit (UTC), or the seconds a secondary limit asks to wait. Both numbers
// are parsed, never quoted.
func rateLimitError(repo string, h http.Header) error {
	if wait, err := strconv.Atoi(h.Get("Retry-After")); err == nil {
		return fmt.Errorf("%s: %w; GitHub asks to retry after %d seconds", repo, ErrRateLimit, wait)
	}
	if reset, err := strconv.ParseInt(h.Get("X-RateLimit-Reset"), 10, 64); err == nil {
		return fmt.Errorf("%s: %w; it resets at %s", repo, ErrRateLimit,
			time.Unix(reset, 0).UTC().Format(time.RFC3339))
	}
	return fmt.Errorf("%s: %w", repo, ErrRateLimit)
}

// list reads the pages of a list from first on: page judges each page's
// body and says whether the next one may still hold wanted items. It stops
// when there is no next page, when page says so, or after maxPages pages;
// it returns true only in that last case with a next page left.
func (c *Client) list(ctx context.Context, repo string, first *url.URL, page func([]byte) (bool, error)) (bool, error) {
	u := first
	for range c.maxPages {
		body, header, err := c.get(ctx, repo, u, jsonMedia)
		if err != nil {
			return false, err
		}
		more, err := page(body)
		if err != nil {
			return false, fmt.Errorf("%s: %w for %s: %w", repo, ErrAnswer, u.EscapedPath(), err)
		}
		if !more {
			return false, nil
		}
		// nil with no next page, and with the error of a foreign one.
		if u, err = c.nextPage(repo, header); u == nil {
			return false, err
		}
	}
	return true, nil
}

// nextPage is the URL of the Link header's rel="next", or nil when there is
// none. A link to any other scheme or host is refused: the token goes to
// the API host only.
func (c *Client) nextPage(repo string, h http.Header) (*url.URL, error) {
	link := nextLink(h.Get("Link"))
	if link == "" {
		return nil, nil
	}
	u, err := url.Parse(link)
	if err != nil || u.Scheme != c.base.Scheme || u.Host != c.base.Host {
		return nil, fmt.Errorf("%s: %w %s", repo, ErrForeignLink, c.base.Host)
	}
	return u, nil
}

// nextLink is the target of rel="next" in a Link header,
// `<url>; rel="next", <url>; rel="last"`, or "".
func nextLink(header string) string {
	for part := range strings.SplitSeq(header, ",") {
		target, params, _ := strings.Cut(part, ";")
		for param := range strings.SplitSeq(params, ";") {
			if strings.TrimSpace(param) == `rel="next"` {
				return strings.Trim(strings.TrimSpace(target), "<>")
			}
		}
	}
	return ""
}
