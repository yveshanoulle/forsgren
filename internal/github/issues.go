package github

import (
	"context"
	"time"
)

// Issue is one issue labelled failure (forsgren#18, step 2).
type Issue struct {
	Number    int64
	CreatedAt time.Time
	ClosedAt  time.Time
	Record    FailureRecord
}

// FailureRecord is the record block of a failure issue's body.
type FailureRecord struct {
	FailureStart            time.Time
	FailedBuild, FixedBuild string
}

// FailureIssues is a stub of forsgren#18 step 2's red.
func (c *Client) FailureIssues(ctx context.Context, repo string, since time.Time) ([]Issue, bool, error) {
	return nil, false, nil
}

// parseRecord is a stub of forsgren#18 step 2's red.
func parseRecord(body string) FailureRecord { return FailureRecord{} }
