package history

import "time"

// Failure is one state of one failure issue (forsgren#18, step 1).
type Failure struct {
	Repository   string // owner/name
	Issue        int64
	OpenedAt     time.Time
	ClosedAt     time.Time
	FailureStart time.Time
}

// LoadFailures is a stub of forsgren#18 step 1's red.
func LoadFailures(path string) ([]Failure, error) { return nil, nil }

// AppendFailures is a stub of forsgren#18 step 1's red.
func AppendFailures(path string, failures []Failure) (int, error) { return 0, nil }
