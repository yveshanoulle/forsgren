package github

import (
	"context"
	"encoding/json"
	"errors"
	"net/url"
	"strings"
	"time"
)

// Issue is one issue labelled failure (forsgren#18, step 2), the fields
// change fail rate needs.
//
// Sure, from GitHub's REST reference for GET /repos/{owner}/{repo}/issues:
// number, created_at, closed_at (null while open) and body (null when
// empty), and that the list holds pull requests too, each with a
// pull_request field. Not sure: the record block is forsgren#6's ruling, a
// convention people write by hand, so a body may hold none, or one in
// another shape; FailureRecord takes only the lines it can read.
type Issue struct {
	Number    int64
	CreatedAt time.Time
	// ClosedAt is zero while the issue is open.
	ClosedAt time.Time
	Record   FailureRecord
}

// FailureRecord is the record block of a failure issue's body: the lines
//
//	failure-start: 2026-09-20T09:12+02:00
//	failed-build: 12.345
//	fixed-build: 12.346
//
// each alone on its line (surrounding spaces and a carriage return
// ignored), the key in lower case, the first of a repeated line winning.
// FailureStart is ISO 8601 with an offset, to the minute or the second, in
// UTC and whole seconds; zero when the line is missing or forsgren cannot
// read its time. A missing build is "".
type FailureRecord struct {
	FailureStart            time.Time
	FailedBuild, FixedBuild string
}

// issue is one item of GitHub's answer, the fields FailureIssues reads.
type issue struct {
	Number      int64           `json:"number"`
	CreatedAt   time.Time       `json:"created_at"`
	ClosedAt    *time.Time      `json:"closed_at"`
	Body        *string         `json:"body"`
	PullRequest json.RawMessage `json:"pull_request"`
}

// errIssueFields: an issue without a number or a creation time.
var errIssueFields = errors.New("an issue has no number or no created_at")

// FailureIssues lists the issues of repo labelled failure, open or closed,
// that were updated at or after since, pull requests left out: GET
// /repos/{owner}/{repo}/issues?labels=failure&state=all&since=..., 100 per
// page, following Link rel="next" up to the page limit; it says whether it
// stopped there. GitHub's since is the update time, so an issue opened
// long ago and closed since is in the list. An issue without a number or a
// created_at is ErrAnswer.
func (c *Client) FailureIssues(ctx context.Context, repo string, since time.Time) ([]Issue, bool, error) {
	query := url.Values{"labels": {"failure"}, "state": {"all"}, "since": {since.UTC().Format(time.RFC3339)}}
	t, err := c.endpoint(repo, query, "issues")
	if err != nil {
		return nil, false, err
	}
	var issues []Issue
	truncated, err := c.list(ctx, t, func(body []byte) (bool, error) {
		var page []issue
		if err := json.Unmarshal(body, &page); err != nil {
			return false, err
		}
		return len(page) > 0, keepIssues(&issues, page)
	})
	if err != nil {
		return nil, false, err
	}
	return issues, truncated, nil
}

// keepIssues adds the issues of one page to issues, pull requests left out.
func keepIssues(issues *[]Issue, page []issue) error {
	for _, i := range page {
		if isPullRequest(i) {
			continue
		}
		if i.Number <= 0 || i.CreatedAt.IsZero() {
			return errIssueFields
		}
		*issues = append(*issues, i.toIssue())
	}
	return nil
}

// isPullRequest says whether an item of the list is a pull request: it has
// a pull_request field that is not null.
func isPullRequest(i issue) bool {
	return len(i.PullRequest) > 0 && string(i.PullRequest) != "null"
}

// toIssue is the Issue of one item.
func (i issue) toIssue() Issue {
	out := Issue{Number: i.Number, CreatedAt: i.CreatedAt.UTC()}
	if i.ClosedAt != nil {
		out.ClosedAt = i.ClosedAt.UTC()
	}
	if i.Body != nil {
		out.Record = parseRecord(*i.Body)
	}
	return out
}

// The keys of the record block.
const (
	keyFailureStart = "failure-start:"
	keyFailedBuild  = "failed-build:"
	keyFixedBuild   = "fixed-build:"
)

// recordTimeLayouts are the forms of failure-start forsgren reads: to the
// minute, as the record block is written, and RFC 3339, to the second or
// a fraction of it.
var recordTimeLayouts = []string{"2006-01-02T15:04Z07:00", time.RFC3339}

// parseRecord reads the record block of an issue's body.
func parseRecord(body string) FailureRecord {
	values := map[string]string{}
	for line := range strings.SplitSeq(body, "\n") {
		line = strings.TrimSpace(line)
		for _, key := range []string{keyFailureStart, keyFailedBuild, keyFixedBuild} {
			if value, ok := strings.CutPrefix(line, key); ok && values[key] == "" {
				values[key] = strings.TrimSpace(value)
			}
		}
	}
	return FailureRecord{
		FailureStart: recordTime(values[keyFailureStart]),
		FailedBuild:  values[keyFailedBuild],
		FixedBuild:   values[keyFixedBuild],
	}
}

// recordTime is s in UTC, whole seconds, or zero when no layout reads it.
func recordTime(s string) time.Time {
	for _, layout := range recordTimeLayouts {
		if t, err := time.Parse(layout, s); err == nil {
			return t.UTC().Truncate(time.Second)
		}
	}
	return time.Time{}
}
