// Package history is the history format v1 (forsgren#12, step 4): the file
// data/deployments.csv in an installation's data repository, which holds the
// deployments `forsgren collect` has found.
//
// The file is CSV, one deployment per line. Its first line states the format
// version, its second names the columns, and every later line is one record:
//
//	# forsgren history v1
//	project,repository,kind,name,deployment_id,commit,created_at,state,task
//	shop,acme/app,environment,production,1001,<40 hex>,2026-09-01T10:00:00Z,success,
//
// The file only grows: a line, once written, is never rewritten or removed.
package history

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const (
	// versionLine is the first line of a v1 file; versionPrefix starts the
	// first line of every version, so another version is told from a stranger.
	versionLine   = "# forsgren history v1"
	versionPrefix = "# forsgren history v"
	// columnLine is the second line of a v1 file.
	columnLine = "project,repository,kind,name,deployment_id,commit,created_at,state,task"
	// timeLayout is created_at: RFC 3339, UTC, whole seconds.
	timeLayout = "2006-01-02T15:04:05Z"
)

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
	// ErrInvalidRecord: a record given to Append cannot be stored.
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

// Load reads the history at path, in file order. A missing file is an error
// wrapping fs.ErrNotExist; a first line stating another version is
// ErrUnknownVersion; a line that is not in the format is a *MalformedError.
func Load(path string) ([]Record, error) {
	data, err := os.ReadFile(filepath.Clean(path))
	if err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	return parse(path, data)
}

// parse reads the content of a history file.
func parse(path string, data []byte) ([]Record, error) {
	lines := strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
	if err := checkHeader(path, lines); err != nil {
		return nil, err
	}
	records := make([]Record, 0, len(lines)-2)
	for i, line := range lines[2:] {
		rec, err := decode(line)
		if err != nil {
			return nil, &MalformedError{Path: path, Line: i + 3, Reason: err.Error()}
		}
		records = append(records, rec)
	}
	return records, nil
}

// checkHeader judges the version line, then the column line.
func checkHeader(path string, lines []string) error {
	switch {
	case lines[0] == versionLine:
	case isVersionLine(lines[0]):
		return fmt.Errorf("%s: %w: %q, this forsgren reads %q", path, ErrUnknownVersion, lines[0], versionLine)
	default:
		return &MalformedError{Path: path, Line: 1, Reason: fmt.Sprintf("want the version line %q", versionLine)}
	}
	if len(lines) < 2 || lines[1] != columnLine {
		return &MalformedError{Path: path, Line: 2, Reason: fmt.Sprintf("want the column line %q", columnLine)}
	}
	return nil
}

// notExist says whether err is a missing file.
func notExist(err error) bool { return errors.Is(err, fs.ErrNotExist) }

// isVersionLine says whether s states a version of the format, any number.
func isVersionLine(s string) bool {
	number, ok := strings.CutPrefix(s, versionPrefix)
	return ok && number != "" && strings.Trim(number, "0123456789") == ""
}
