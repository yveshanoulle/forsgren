package history

import (
	"cmp"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"time"
)

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

// reachRow is one line of data/reach.csv.
type reachRow struct {
	Repository string // owner/name
	Reach      time.Time
}

// reachFile is the format of data/reach.csv, the reach format v1. Unlike the
// other files it is rewritten whole (SaveReach), never appended to.
var reachFile = format[reachRow, string]{
	versionLine: "# forsgren reach v1",
	columnLine:  "repository,reach",
	decode:      toReachRow,
	encode:      reachRow.fields,
	validate:    reachRow.validate,
	key:         func(r reachRow) string { return r.Repository },
	compare:     func(a, b reachRow) int { return cmp.Compare(a.Repository, b.Repository) },
}

// toReachRow reads the two fields of a line.
func toReachRow(f []string) (reachRow, error) {
	at, err := parseTime("reach", f[1])
	return reachRow{Repository: f[0], Reach: at}, err
}

// fields are the columns of r's line.
func (r reachRow) fields() []string {
	return []string{r.Repository, r.Reach.UTC().Format(timeLayout)}
}

// validate says why r cannot be stored, or nil.
func (r reachRow) validate() error {
	return firstFailure(
		check{isRepository(r.Repository), fmt.Sprintf("repository %q is not owner/name", r.Repository)},
		check{isWholeSecond(r.Reach), "reach is empty or has a fraction of a second"},
	)
}

// LoadReach reads the reach at path. A missing file is an empty Reach, not an
// error; a first line stating another version is ErrUnknownVersion; a line
// that is not in the format is a *MalformedError naming the file and the
// line.
func LoadReach(path string) (Reach, error) {
	rows, err := reachFile.load(path)
	if notExist(err) {
		return Reach{}, nil
	}
	if err != nil {
		return nil, err
	}
	reach := make(Reach, len(rows))
	for _, row := range rows {
		reach[row.Repository] = row.Reach
	}
	return reach, nil
}

// SaveReach writes r to path whole, sorted by repository, creating the
// directory when it is missing, and replacing a file that is there. The
// content goes to a temporary file next to it, synced, and is then renamed
// over path, so a crash never leaves half a file.
func SaveReach(path string, r Reach) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		return fmt.Errorf("%s: %w", path, err)
	}
	rows := make([]reachRow, 0, len(r))
	for repository, at := range r {
		rows = append(rows, reachRow{repository, at})
	}
	slices.SortFunc(rows, reachFile.compare)
	temporary := path + ".tmp"
	if err := writeSynced(temporary, reachFile.payload(store[reachRow]{}, rows)); err != nil {
		return err
	}
	if err := os.Rename(temporary, path); err != nil {
		return errors.Join(fmt.Errorf("%s: %w", path, err), os.Remove(temporary))
	}
	return nil
}

// writeSynced writes data to a file of its own at path, replacing what is
// there, and syncs it to disk.
func writeSynced(path string, data []byte) error {
	file, err := os.OpenFile(filepath.Clean(path), os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o600)
	if err != nil {
		return fmt.Errorf("%s: %w", path, err)
	}
	_, werr := file.Write(data)
	return errors.Join(werr, file.Sync(), file.Close())
}
