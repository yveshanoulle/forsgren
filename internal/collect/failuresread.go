package collect

// When the issues of each repository were last read (forsgren#67):
// data/failures_read.csv, next to the history, one time per repository. A run
// asks for the issues updated since that time less a day; with none, since
// history_days before Now. The time moves to Now when the repository's
// issues were read and stored, and stays when they were not. The failure
// issues and, since forsgren#76 (decision #101), the issue events share it:
// both are read in the same repository step and the mark moves only once
// both are stored.

import (
	"errors"
	"maps"
	"path/filepath"
	"strings"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// FailuresReadFile is the name, next to the history, of the file that notes
// when each repository's failure issues were last read.
const FailuresReadFile = "failures_read.csv"

// failuresReadOverlap is how far before its last read a run asks again, so
// an issue updated while the last run was reading is not missed.
const failuresReadOverlap = 24 * time.Hour

// marks are the two files that note how far each repository was read.
type marks struct{ reach, read history.Reach }

// marks is a copy of h's marks, to tell later whether they moved.
func (h held) marks() marks { return marks{maps.Clone(h.reach), maps.Clone(h.read)} }

// failuresReadFile is the path of the failures read file next to the history.
func (o Options) failuresReadFile() string {
	return filepath.Join(filepath.Dir(o.History), FailuresReadFile)
}

// loadMarks is h with the reach and the failures read files loaded; a file
// that cannot be read refuses the run.
func (o Options) loadMarks(h held) (held, error) {
	var err error
	if h.reach, err = history.LoadReach(o.reachFile()); err != nil {
		return h, err
	}
	h.read, err = history.LoadReadAt(o.failuresReadFile())
	return h, err
}

// saveMarks saves each of h's marks that differs from before.
func (o Options) saveMarks(h held, before marks) error {
	var errs []error
	if !maps.Equal(h.reach, before.reach) {
		errs = append(errs, history.SaveReach(o.reachFile(), h.reach))
	}
	if !maps.Equal(h.read, before.read) {
		errs = append(errs, history.SaveReadAt(o.failuresReadFile(), h.read))
	}
	return errors.Join(errs...)
}

// issuesSince is where the reads of repo's issues start, the failure issues
// and every issue for its events alike.
func (o Options) issuesSince(h held, repo string) time.Time {
	if last, ok := h.read[strings.ToLower(repo)]; ok {
		return last.Add(-failuresReadOverlap)
	}
	return o.earliest
}

// noteRead moves repo's issues read to at, whole seconds, UTC.
func (h held) noteRead(repo string, at time.Time) {
	h.read[strings.ToLower(repo)] = wholeSecond(at)
}

// wholeSecond is t in UTC, whole seconds, as the files store times.
func wholeSecond(t time.Time) time.Time { return t.UTC().Truncate(time.Second) }
