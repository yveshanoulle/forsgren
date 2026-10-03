// Package history is what `forsgren collect` keeps in an installation's data
// repository: three append-only CSV files, each with its own format version.
//
// The deployments, data/deployments.csv (the history format v1, forsgren#12,
// step 4), one deployment per line:
//
//	# forsgren history v1
//	project,repository,kind,name,deployment_id,commit,created_at,state,task
//	shop,acme/app,environment,production,1001,<40 hex>,2026-09-01T10:00:00Z,success,
//
// The commits of each successful deployment, data/commits.csv (the commits
// format v1, forsgren#16, step 1), one line per commit per deployment, for
// lead time:
//
//	# forsgren commits v1
//	repository,kind,deployment_id,commit,authored_at,deployed_at
//	acme/app,environment,1001,<40 hex>,2026-09-01T09:00:00Z,2026-09-01T10:00:00Z
//
// The failure issues of the configured repositories, data/failures.csv (the
// failures format v1, forsgren#18, step 1), one line per state of an issue
// (open, closed, reopened), the newest line of an issue winning, for change
// fail rate:
//
//	# forsgren failures v1
//	repository,issue,opened_at,closed_at,failure_start
//	acme/app,42,2026-09-01T10:00:00Z,,2026-09-01T09:30:00Z
//
// In all three, the first line states the format version, the second names
// the columns, and every later line is one record. A file only grows: a
// line, once written, is never rewritten or removed.
package history

import (
	"errors"
	"fmt"
	"time"
)

// timeLayout is every time in the files: RFC 3339, UTC, whole seconds.
const timeLayout = "2006-01-02T15:04:05Z"

// Kind says how a deployment was found: by the repository's rule.
type Kind string

// The three kinds, as configured in forsgren.config.yml.
const (
	KindEnvironment Kind = "environment"
	KindWorkflow    Kind = "workflow"
	KindRelease     Kind = "release"
)

// State is the final state of a deployment. Only final states are stored: a
// deployment that is still running is not recorded until it has finished.
type State string

// The three final states. Other is any final state that is neither a success
// nor a failure.
const (
	StateSuccess State = "success"
	StateFailure State = "failure"
	StateOther   State = "other"
)

// Record is one deployment. CreatedAt is UTC and whole seconds.
type Record struct {
	Project    string
	Repository string // owner/name
	Kind       Kind
	Name       string // the environment or the workflow file; empty for a release
	ID         int64  // the deployment's ID at GitHub (a run or release ID for those kinds)
	Commit     string // the commit SHA, lower-case hex
	CreatedAt  time.Time
	State      State
	Task       string // may be empty
}

// The refusals; every error the package returns wraps one of them, except a
// failure of the file system, which wraps the file system's own error.
var (
	// ErrUnknownVersion: the first line states a version this forsgren does
	// not know.
	ErrUnknownVersion = errors.New("unknown history format version")
	// ErrMalformed: a line is not what the format says; the error is a
	// *MalformedError with the line number.
	ErrMalformed = errors.New("malformed history")
	// ErrInvalidRecord: a record given to Append, AppendCommits or
	// AppendFailures cannot be stored.
	ErrInvalidRecord = errors.New("invalid history record")
)

// MalformedError names the line of a history file that is not in the format.
type MalformedError struct {
	Path   string
	Line   int // 1-based
	Reason string
}

func (e *MalformedError) Error() string {
	return fmt.Sprintf("%s: line %d: %s: %s", e.Path, e.Line, ErrMalformed, e.Reason)
}

// Is makes errors.Is(err, ErrMalformed) true.
func (e *MalformedError) Is(target error) bool { return target == ErrMalformed }

// Load reads the deployments at path, in file order. A missing file is an
// error wrapping fs.ErrNotExist; a first line stating another version is
// ErrUnknownVersion; a line that is not in the format is a *MalformedError.
func Load(path string) ([]Record, error) { return deployments.load(path) }
