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

// markFile is one of the files next to the history that keep a time per
// repository (history.Reach): where held keeps it during the run, its path,
// and how it is read and written.
type markFile struct {
	held *history.Reach
	path string
	load func(path string) (history.Reach, error)
	save func(path string, r history.Reach) error
}

// markFiles are h's eleven marks, in the order they are loaded and saved: how
// far each repository was read (reach, chunk.go), when its issues were last
// read (read), whether they were read in full (full, issueevents.go) and
// where its bug read was cut (cut, bugflags.go) and since when it has been
// cut short at the request budget without progress (cutRuns, report.go) and
// which repositories had their failure starts caught up from the comments
// (checked, startscatchup.go) and when its closed pull requests were last
// read (pullsRead, pulls.go) and whether that read was last refused (denied,
// pulls.go) and when its pushes to main were last read (pushesRead,
// pushes.go) and whether that read was last refused (pushesDenied,
// pushes.go) and which repositories had their legacy commits backfilled
// (backfilled, legacybackfill.go).
func (o Options) markFiles(h *held) []markFile {
	return []markFile{
		{&h.reach, o.reachFile(), history.LoadReach, history.SaveReach},
		{&h.read, o.failuresReadFile(), history.LoadReadAt, history.SaveReadAt},
		{&h.full, o.issuesFullFile(), history.LoadFullAt, history.SaveFullAt},
		{&h.cut, o.bugsCutFile(), history.LoadBugsCut, history.SaveBugsCut},
		{&h.cutRuns, o.cutRunsFile(), history.LoadCutRuns, history.SaveCutRuns},
		{&h.checked, o.startsCheckedFile(), history.LoadStartsChecked, history.SaveStartsChecked},
		{&h.pullsRead, o.pullsReadFile(), history.LoadPullsRead, history.SavePullsRead},
		deniedFile(&h.denied, &h.deniedBy, o.pullsDeniedFile(), history.LoadPullsDenied, history.SavePullsDenied),
		{&h.pushesRead, o.pushesReadFile(), history.LoadPushesRead, history.SavePushesRead},
		deniedFile(&h.pushesDenied, &h.pushesDeniedBy, o.pushesDeniedFile(),
			history.LoadPushesDenied, history.SavePushesDenied),
		{&h.backfilled, o.commitsBackfilledFile(), history.LoadCommitsBackfilled, history.SaveCommitsBackfilled},
	}
}

// marks are copies of h's marks, in markFiles' order.
type marks []history.Reach

// marks is a copy of h's marks, to tell later whether they moved.
func (o Options) marks(h held) marks {
	files := o.markFiles(&h)
	copies := make(marks, len(files))
	for i, f := range files {
		copies[i] = maps.Clone(*f.held)
	}
	return copies
}

// CutRunsFile is the name, next to the history, of the file that notes since
// when a repository has been cut short at the request budget without keeping
// a day (forsgren#64, step 3b).
const CutRunsFile = "cut_runs.csv"

// cutRunsFile is the path of the cut runs file next to o's history.
func (o Options) cutRunsFile() string { return filepath.Join(filepath.Dir(o.History), CutRunsFile) }

// failuresReadFile is the path of the failures read file next to the history.
func (o Options) failuresReadFile() string {
	return filepath.Join(filepath.Dir(o.History), FailuresReadFile)
}

// loadMarks is h with each of its mark files loaded; a file that cannot be
// read refuses the run.
func (o Options) loadMarks(h held) (held, error) {
	var errs []error
	for _, f := range o.markFiles(&h) {
		var err error
		*f.held, err = f.load(f.path)
		errs = append(errs, err)
	}
	return h, errors.Join(errs...)
}

// saveMarks saves each of h's marks that differs from before.
func (o Options) saveMarks(h held, before marks) error {
	var errs []error
	for i, f := range o.markFiles(&h) {
		if !maps.Equal(*f.held, before[i]) {
			errs = append(errs, f.save(f.path, *f.held))
		}
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
