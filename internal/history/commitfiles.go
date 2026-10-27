package history

import (
	"cmp"
	"fmt"
	"strings"
)

// CommitFile is one file a deployed commit changes (forsgren#496, step 3): a
// line of data/commit_files.csv, which the service rows read to count only
// the commits that touch the service's paths. It holds the repository-relative
// path, never the content, and for a rename both the new and the old path.
//
// The format is "# forsgren commit files v1", the column line
// "repository,sha,path". A commit that was read and changes no file (a merge
// commit may list none) is one line with an empty Path, so it is not read
// again: absent means not read yet, an empty path means read, nothing
// changed. A commit read cut at GitHub's 3000 files is stored as read.
type CommitFile struct {
	Repository string // owner/name
	SHA        string // the commit, lower-case hex
	Path       string // repository-relative; empty: the commit changes no file
}

// commitFiles is the format of data/commit_files.csv, the commit files
// format v1.
var commitFiles = format[CommitFile, commitFileKey]{
	versionLine: "# forsgren commit files v1",
	columnLine:  "repository,sha,path",
	decode:      toCommitFile,
	encode:      CommitFile.fields,
	validate:    CommitFile.validate,
	key:         CommitFile.key,
	compare:     compareCommitFiles,
}

// LoadCommitFiles reads the commit files at path, in file order, with Load's
// errors.
func LoadCommitFiles(path string) ([]CommitFile, error) { return commitFiles.load(path) }

// AppendCommitFiles stores the lines that the file at path does not hold yet,
// and returns how many it stored, by Append's rules. A line is already held
// when one has the same repository (ignoring case), commit SHA and path. The
// new lines are in the order of repository, SHA, path.
func AppendCommitFiles(path string, records []CommitFile) (int, error) {
	return commitFiles.append(path, records)
}

// commitFileKey identifies a path of a commit.
type commitFileKey struct{ repository, sha, path string }

// key is f's repository (lower-case), commit and path.
func (f CommitFile) key() commitFileKey {
	return commitFileKey{strings.ToLower(f.Repository), f.SHA, f.Path}
}

// compareCommitFiles orders new lines by repository, SHA, path.
func compareCommitFiles(a, b CommitFile) int {
	return cmp.Or(cmp.Compare(a.Repository, b.Repository), cmp.Compare(a.SHA, b.SHA), cmp.Compare(a.Path, b.Path))
}

// fields are the columns of f's line.
func (f CommitFile) fields() []string { return []string{f.Repository, f.SHA, f.Path} }

// toCommitFile reads the three fields of a line.
func toCommitFile(f []string) (CommitFile, error) {
	return CommitFile{Repository: f[0], SHA: f[1], Path: f[2]}, nil
}

// validate says why f cannot be stored, or nil.
func (f CommitFile) validate() error {
	return firstFailure(
		check{isRepository(f.Repository), fmt.Sprintf("repository %q is not owner/name", f.Repository)},
		check{!strings.ContainsAny(f.Repository, "\r\n"), "repository has a line break"},
		check{isSHA(f.SHA), fmt.Sprintf("sha %q is not 40 or 64 lower-case hex digits", f.SHA)},
		check{!strings.ContainsAny(f.Path, "\r\n"), "path has a line break"},
	)
}

// commitFilesFilledFile is the format of data/commit_files_filled.csv, the
// commit files filled format v1 (forsgren#496): the rows of the reach format,
// with a version line and a column that say what the time is, when the
// one-time fill of the files of the repository's stored commits was done.
var commitFilesFilledFile = markFormat("# forsgren commit files filled v1", "repository,filled_at")

// LoadCommitFilesFilled reads data/commit_files_filled.csv at path: per
// repository, when its fill was done. Missing is empty, like LoadReach.
func LoadCommitFilesFilled(path string) (Reach, error) { return loadReach(path, commitFilesFilledFile) }

// SaveCommitFilesFilled writes r to path whole, in the commit files filled
// format v1, like SaveReach.
func SaveCommitFilesFilled(path string, r Reach) error {
	return saveReach(path, r, commitFilesFilledFile)
}
