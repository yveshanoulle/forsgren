package github

import (
	"context"
	"time"
)

// Commit is one commit of a comparison (forsgren#16, step 2).
type Commit struct {
	SHA        string
	AuthoredAt time.Time
}

// Compare is a stub of forsgren#16 step 2's red.
func (c *Client) Compare(ctx context.Context, repo, base, head string) ([]Commit, bool, error) {
	return nil, false, nil
}
