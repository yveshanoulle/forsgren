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
	ErrMissingTag     = errors.New("the release's tag is missing")
	ErrCommitSHA      = errors.New("not a 40-hex commit SHA")
	ErrNotAncestor    = errors.New("the base is not an ancestor of the head")
	ErrMissingCommit  = errors.New("a commit of the comparison is missing")
)

// Client reads GitHub's REST API at one base URL with one token.
type Client struct {
	base     *url.URL
	token    string
	maxPages int
	http     *http.Client
	// tokenName is the environment variable the token came from, which a
	// refusal tells the caller to check.
	tokenName string
}

// defaultTokenName is the token a refusal names unless WithTokenName says
// otherwise: the installation's own, the one collect reads with.
const defaultTokenName = "FORSGREN_TOKEN"

// New is a client of the API at baseURL (https://api.github.com, or a test
// server) that reads at most maxPages pages per list, and at least one. A
// refusal names FORSGREN_TOKEN as the token to check; WithTokenName names
// another.
func New(baseURL, token string, maxPages int) (*Client, error) {
	u, err := url.Parse(baseURL)
	if err != nil || !isWebURL(u) {
		return nil, fmt.Errorf("%w: %q", ErrBaseURL, baseURL)
	}
	u.Path = "/" + strings.TrimPrefix(u.Path, "/")
	return &Client{base: u, token: token, maxPages: max(maxPages, 1), http: &http.Client{Timeout: time.Minute},
		tokenName: defaultTokenName}, nil
}

// WithTokenName makes a refusal name name, the environment variable the
// token came from (GITHUB_TOKEN for the workflow job's token), as the token
// to check, and returns c.
func (c *Client) WithTokenName(name string) *Client {
	c.tokenName = name
	return c
}

// isWebURL says whether u is an absolute http or https URL with a host.
func isWebURL(u *url.URL) bool {
	switch u.Scheme {
	case "https", "http":
		return u.Host != ""
	}
	return false
}

// MaxPages is how many pages one list reads at most.
func (c *Client) MaxPages() int { return c.maxPages }

// repositoryName is GitHub's owner/name, as config checks it.
var repositoryName = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9._-]+$`)

// IsRepositoryName says whether repo is one owner/name, which every call of
// the client requires before it makes a URL of it, for a caller that checks
// its flag first.
func IsRepositoryName(repo string) bool { return isRepositoryName(repo) }

// isRepositoryName says whether repo is one owner/name whose name is not .
// or .., which a URL path would resolve to another place.
func isRepositoryName(repo string) bool {
	if !repositoryName.MatchString(repo) {
		return false
	}
	_, name, _ := strings.Cut(repo, "/")
	return name != "." && name != ".."
}

// target is one request: the repository it is about, which every error
// names, and its URL.
type target struct {
	repo string
	url  *url.URL
}

// path is the target's URL path, escaped, as errors show it: never the
// query, never the host.
func (t target) path() string { return t.url.EscapedPath() }

// endpoint is the target of a path under /repos/{owner}/{name}, with query
// and 100 per page; the repository name is checked first, so a name that is
// not one owner/name never becomes a URL.
func (c *Client) endpoint(repo string, query url.Values, segments ...string) (target, error) {
	if !isRepositoryName(repo) {
		return target{}, fmt.Errorf("%w: %q", ErrRepositoryName, repo)
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
	return target{repo: repo, url: u}, nil
}

// get fetches t with the token and the media type accept: the body of a 2xx
// answer and its headers, or an error that names t's repository.
func (c *Client) get(ctx context.Context, t target, accept string) ([]byte, http.Header, error) {
	return c.do(ctx, call{method: http.MethodGet, accept: accept, t: t})
}

// call is one request of do: the HTTP method, the media type to accept, the
// target and the JSON body to send, nil for none.
type call struct {
	method string
	accept string
	t      target
	body   io.Reader
}

// request is the HTTP request of k with the token, the media type and, for a
// body, its content type.
func (c *Client) request(ctx context.Context, k call) (*http.Request, error) {
	req, err := http.NewRequestWithContext(ctx, k.method, k.t.url.String(), k.body)
	if err != nil {
		return nil, fmt.Errorf("%s: %w", k.t.repo, err)
	}
	if c.token != "" {
		req.Header.Set("Authorization", "Bearer "+c.token)
	}
	if k.body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	req.Header.Set("Accept", k.accept)
	req.Header.Set("X-GitHub-Api-Version", apiVersion)
	req.Header.Set("User-Agent", "forsgren")
	return req, nil
}

// do sends the call with the token: the body of a 2xx answer and its headers,
// or an error that names the repository of the call's target.
func (c *Client) do(ctx context.Context, k call) ([]byte, http.Header, error) {
	t := k.t
	req, err := c.request(ctx, k)
	if err != nil {
		return nil, nil, err
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, nil, fmt.Errorf("%s: cannot reach GitHub: %w", t.repo, err)
	}
	defer func() { _ = resp.Body.Close() }()
	if err := statusError(t, resp, c.tokenName); err != nil {
		return nil, nil, err
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxBody))
	if err != nil {
		return nil, nil, fmt.Errorf("%s: %w for %s: %w", t.repo, ErrAnswer, t.path(), err)
	}
	return body, resp.Header, nil
}

// answerError is GitHub's error answer: its status code, for a caller that
// knows what a code means for its own call, and the error that says what to
// do in general.
type answerError struct {
	code int
	err  error
}

func (e *answerError) Error() string { return e.err.Error() }

func (e *answerError) Unwrap() error { return e.err }

// status is the answer's code and its text, 404 Not Found.
func (e *answerError) status() string { return fmt.Sprintf("%d %s", e.code, http.StatusText(e.code)) }

// statusError is nil for a 2xx answer, else an *answerError that says what
// to do; a refusal names tokenName as the token to check. It never quotes
// the answer's body or headers: an answer can echo anything.
func statusError(t target, resp *http.Response, tokenName string) error {
	code := resp.StatusCode
	if code >= 200 && code < 300 {
		return nil
	}
	e := &answerError{code: code}
	switch {
	case isRateLimited(resp):
		e.err = rateLimitError(t, resp.Header)
	case isRefused(code):
		e.err = fmt.Errorf("%s: %w: %s for %s; check %s's access to %s",
			t.repo, ErrAccess, e.status(), t.path(), tokenName, t.repo)
	default:
		e.err = fmt.Errorf("%s: %w: %s for %s", t.repo, ErrStatus, e.status(), t.path())
	}
	return e
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
func rateLimitError(t target, h http.Header) error {
	if wait, err := strconv.Atoi(h.Get("Retry-After")); err == nil {
		return fmt.Errorf("%s: %w; GitHub asks to retry after %d seconds", t.repo, ErrRateLimit, wait)
	}
	if reset, err := strconv.ParseInt(h.Get("X-RateLimit-Reset"), 10, 64); err == nil {
		return fmt.Errorf("%s: %w; it resets at %s", t.repo, ErrRateLimit,
			time.Unix(reset, 0).UTC().Format(time.RFC3339))
	}
	return fmt.Errorf("%s: %w", t.repo, ErrRateLimit)
}

// list reads the pages of a list from first on: page judges each page's
// body and says whether the next one may still hold wanted items. It stops
// when there is no next page, when page says so, or after maxPages pages;
// it returns true only in that last case with a next page left.
func (c *Client) list(ctx context.Context, first target, page func([]byte) (bool, error)) (bool, error) {
	t := first
	for range c.maxPages {
		body, header, err := c.get(ctx, t, jsonMedia)
		if err != nil {
			return false, err
		}
		more, err := page(body)
		if err != nil {
			return false, fmt.Errorf("%s: %w for %s: %w", t.repo, ErrAnswer, t.path(), err)
		}
		if !more {
			return false, nil
		}
		// nil with no next page, and with the error of a foreign one.
		if t.url, err = c.nextPage(t, header); t.url == nil {
			return false, err
		}
	}
	return true, nil
}

// nextPage is the URL of the Link header's rel="next" in the answer to t,
// or nil when there is none. A link to any other scheme or host is refused:
// the token goes to the API host only.
func (c *Client) nextPage(t target, h http.Header) (*url.URL, error) {
	link := nextLink(h.Get("Link"))
	if link == "" {
		return nil, nil
	}
	u, err := url.Parse(link)
	if err != nil || !c.onAPIHost(u) {
		return nil, fmt.Errorf("%s: %w %s", t.repo, ErrForeignLink, c.base.Host)
	}
	return u, nil
}

// onAPIHost says whether u has the scheme and the host of the API's base URL.
func (c *Client) onAPIHost(u *url.URL) bool {
	return u.Scheme == c.base.Scheme && u.Host == c.base.Host
}

// nextLink is the target of rel="next" in a Link header,
// `<url>; rel="next", <url>; rel="last"`, or "".
func nextLink(header string) string {
	for part := range strings.SplitSeq(header, ",") {
		ref, params, _ := strings.Cut(part, ";")
		for param := range strings.SplitSeq(params, ";") {
			if strings.TrimSpace(param) == `rel="next"` {
				return strings.Trim(strings.TrimSpace(ref), "<>")
			}
		}
	}
	return ""
}
