package history

// data/commit_files_progress.csv (forsgren#594, step 1), the commit files
// progress format v1: per repository whose commit files read is still going,
// how many of its commits have file lines and how many are left, as collect
// counted them at the end of its last read (forsgren#593's counts, which the
// run's report gives too). A repository is there only while commits are left,
// so the Data page, which is rendered from the data files and not from the
// run's report, can say how far the read is. Rewritten whole, like the mark
// files.

import (
	"cmp"
	"fmt"
	"strconv"
)

// FilesProgress is how far a repository's commit files read is: the commits
// with file lines and the commits left to read.
type FilesProgress struct {
	Read int
	Left int
}

// CommitFilesProgress is data/commit_files_progress.csv: per repository, how
// far its commit files read is.
type CommitFilesProgress map[string]FilesProgress

// progressRow is one line of data/commit_files_progress.csv.
type progressRow struct {
	Repository string // owner/name
	FilesProgress
}

// commitFilesProgressFile is the format of data/commit_files_progress.csv.
var commitFilesProgressFile = format[progressRow, string]{
	versionLine: "# forsgren commit files progress v1",
	columnLine:  "repository,read,left",
	decode:      toProgressRow,
	encode:      progressRow.fields,
	validate:    progressRow.validate,
	compare:     func(a, b progressRow) int { return cmp.Compare(a.Repository, b.Repository) },
}

// toProgressRow reads the three fields of a line.
func toProgressRow(f []string) (progressRow, error) {
	read, err := parseNumber("read", f[1])
	if err != nil {
		return progressRow{}, err
	}
	left, err := parseNumber("left", f[2])
	return progressRow{Repository: f[0], FilesProgress: FilesProgress{Read: int(read), Left: int(left)}}, err
}

// fields are the columns of r's line.
func (r progressRow) fields() []string {
	return []string{r.Repository, strconv.Itoa(r.Read), strconv.Itoa(r.Left)}
}

// validate says why r cannot be stored, or nil: a line is a read still going,
// so at least one commit is left.
func (r progressRow) validate() error {
	return firstFailure(
		check{isRepository(r.Repository), fmt.Sprintf("repository %q is not owner/name", r.Repository)},
		check{r.Read >= 0, fmt.Sprintf("read %d is below zero", r.Read)},
		check{r.Left > 0, fmt.Sprintf("left %d is no commit left", r.Left)},
	)
}

// LoadCommitFilesProgress reads data/commit_files_progress.csv at path. A
// missing file is empty, like LoadReach; a first line stating another version
// is ErrUnknownVersion; a line that is not in the format is a *MalformedError.
func LoadCommitFilesProgress(path string) (CommitFilesProgress, error) {
	rows, err := commitFilesProgressFile.load(path)
	if notExist(err) {
		return CommitFilesProgress{}, nil
	}
	if err != nil {
		return nil, err
	}
	progress := make(CommitFilesProgress, len(rows))
	for _, row := range rows {
		progress[row.Repository] = row.FilesProgress
	}
	return progress, nil
}

// SaveCommitFilesProgress writes p to path whole, sorted by repository, like
// SaveReach. A line the format cannot store is refused before anything is
// written.
func SaveCommitFilesProgress(path string, p CommitFilesProgress) error {
	rows := make([]progressRow, 0, len(p))
	for repository, progress := range p {
		rows = append(rows, progressRow{repository, progress})
	}
	return saveRows(path, rows, commitFilesProgressFile)
}
