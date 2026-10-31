package collect

// The progress of the commit files read (forsgren#594, step 1):
// data/commit_files_progress.csv keeps, per repository whose read is still
// going, the commits read and those left, forsgren#593's counts, so the Data
// page, which is rendered from the data files and never sees a run's report,
// can say how far the read is. The counts come from the lines already stored
// and the todo, no request (filesTodo.capped), so they are known whatever
// ended the read: the cap, a budget stop, a refusal or another error each
// keep the line at what the read reached, and a read that got past every
// commit of its todo (a commit GitHub does not have included, as for
// push_files_filled.csv) removes it. A repository whose read does not start
// (no paths, its stored commits unreadable, or the run never reached it)
// keeps its line as it was. The file is rewritten whole when a line changes,
// right after the commit files are stored, so it never runs ahead of them.

import (
	"path/filepath"
	"strings"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// commitFilesProgressFile is the path of the commit files progress file next
// to o's history.
func (o Options) commitFilesProgressFile() string {
	return filepath.Join(filepath.Dir(o.History), CommitFilesProgressFile)
}

// storeFiles stores the lines read gave, notes the file marks of at's
// repository and keeps its progress at at's counts.
func (o Options) storeFiles(h held, at CappedFiles, todo filesTodo, read fileRead) error {
	if _, err := history.AppendCommitFiles(o.commitFilesFile(), read.lines); err != nil {
		return err
	}
	o.noteFileMarks(h, at.Repository, todo, read)
	return o.noteFilesProgress(h, at)
}

// noteFilesProgress sets at's repository's line to at's counts while commits
// are left, removes it when none is, and saves the file when the line moved.
func (o Options) noteFilesProgress(h held, at CappedFiles) error {
	repo := strings.ToLower(at.Repository)
	was, going := h.filesProgress[repo]
	now := history.FilesProgress{Read: at.Read, Left: at.Left}
	switch {
	case at.Left > 0 && was != now:
		h.filesProgress[repo] = now
	case at.Left == 0 && going:
		delete(h.filesProgress, repo)
	default:
		return nil
	}
	return history.SaveCommitFilesProgress(o.commitFilesProgressFile(), h.filesProgress)
}
