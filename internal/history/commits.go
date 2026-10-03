package history

import "time"

// Commit is one commit of one successful deployment (forsgren#16, step 1).
type Commit struct {
	Repository   string // owner/name
	Kind         Kind
	DeploymentID int64
	SHA          string
	AuthoredAt   time.Time
	DeployedAt   time.Time
}

// LoadCommits is a stub of forsgren#16 step 1's red.
func LoadCommits(path string) ([]Commit, error) { return nil, nil }

// AppendCommits is a stub of forsgren#16 step 1's red.
func AppendCommits(path string, commits []Commit) (int, error) { return 0, nil }
