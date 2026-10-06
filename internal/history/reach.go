package history

import "time"

// Reach is how far back each repository's history has been read
// (forsgren#57): the date, per repository (owner/name), down to which
// collect has read it, kept in data/reach.csv, because the oldest stored
// deployment cannot tell a quiet stretch from an unread one.
//
// The file is the reach format v1: a version line, a column line, then one
// line per repository, sorted by repository:
//
//	# forsgren reach v1
//	repository,reach
//	acme/app,2026-06-01T00:00:00Z
type Reach map[string]time.Time

// LoadReach reads the reach at path. A missing file is an empty Reach, not an
// error; a first line stating another version is ErrUnknownVersion; a line
// that is not in the format is a *MalformedError naming the file and the
// line.
func LoadReach(path string) (Reach, error) { return nil, nil }

// SaveReach writes r to path whole, sorted by repository, creating the
// directory when it is missing, and replacing a file that is there.
func SaveReach(path string, r Reach) error { return nil }
