package github

import (
	"context"
	"encoding/json"
	"net/url"
	"strconv"
)

// comment is one item of GitHub's answer to an issue's comments: the body
// is null when empty.
type comment struct {
	Body *string `json:"body"`
}

// CommentRecords reads the comments of issue number of repo (forsgren#37)
// and returns the record block of each, in the order GitHub lists them,
// oldest first: GET /repos/{owner}/{repo}/issues/{number}/comments, 100 per
// page, following Link rel="next" up to the page limit; it says whether it
// stopped there. A comment without a block, or without a body, is an empty
// record: the blocks of different comments are never combined. A refused
// read is an error, never an empty answer.
func (c *Client) CommentRecords(ctx context.Context, repo string, number int64) ([]FailureRecord, bool, error) {
	t, err := c.endpoint(repo, url.Values{}, "issues", strconv.FormatInt(number, 10), "comments")
	if err != nil {
		return nil, false, err
	}
	var records []FailureRecord
	truncated, err := c.listUpTo(ctx, t, c.maxPages, func(body []byte) (bool, error) {
		var page []comment
		if err := json.Unmarshal(body, &page); err != nil {
			return false, err
		}
		for _, cm := range page {
			var record FailureRecord
			if cm.Body != nil {
				record = parseRecord(*cm.Body)
			}
			records = append(records, record)
		}
		return len(page) > 0, nil
	})
	if err != nil {
		return nil, false, err
	}
	return records, truncated, nil
}
