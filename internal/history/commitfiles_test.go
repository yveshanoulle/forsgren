package history

import (
	"path/filepath"
	"strings"
	"testing"
)

const (
	commitFilesHead = "# forsgren commit files v1\nrepository,sha,path\n"
	commitFilesSHA  = "7777777777777777777777777777777777777777"
)

// TestACommitFileIsWrittenOnceByRepositorySHAAndPath (forsgren#496, step 3):
// data/commit_files.csv is created with its version and column lines; a line
// already held (repository ignoring case, commit SHA and path) is not written
// again; the new lines go by repository, SHA, path.
func TestACommitFileIsWrittenOnceByRepositorySHAAndPath(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data", "commit_files.csv")
	first := []CommitFile{{"acme/app", commitFilesSHA, "web/b.go"}, {"acme/app", commitFilesSHA, "api/a.go"}}
	if n, err := AppendCommitFiles(path, first); err != nil || n != 2 {
		t.Fatalf("want 2 lines written, got %d, %v", n, err)
	}
	again := []CommitFile{{"ACME/app", commitFilesSHA, "api/a.go"}, {"acme/app", commitFilesSHA, "go.mod"}}
	if n, err := AppendCommitFiles(path, again); err != nil || n != 1 {
		t.Fatalf("want 1 new line written, got %d, %v", n, err)
	}
	wantFile(t, path, commitFilesHead+
		"acme/app,"+commitFilesSHA+",api/a.go\n"+
		"acme/app,"+commitFilesSHA+",web/b.go\n"+
		"acme/app,"+commitFilesSHA+",go.mod\n")
	wantLoaded(t, path, LoadCommitFiles, []CommitFile{
		{"acme/app", commitFilesSHA, "api/a.go"}, {"acme/app", commitFilesSHA, "web/b.go"},
		{"acme/app", commitFilesSHA, "go.mod"}})
}

// TestACommitReadWithNoFilesIsAnEmptyPath: the marker of a commit that was
// read and changes no file is a line with an empty path, which is held like
// any other.
func TestACommitReadWithNoFilesIsAnEmptyPath(t *testing.T) {
	path := filepath.Join(t.TempDir(), "commit_files.csv")
	marker := []CommitFile{{"acme/app", commitFilesSHA, ""}}
	if n, err := AppendCommitFiles(path, marker); err != nil || n != 1 {
		t.Fatalf("want the marker written, got %d, %v", n, err)
	}
	if n, err := AppendCommitFiles(path, marker); err != nil || n != 0 {
		t.Fatalf("want the marker held, got %d, %v", n, err)
	}
	wantFile(t, path, commitFilesHead+"acme/app,"+commitFilesSHA+",\n")
	wantLoaded(t, path, LoadCommitFiles, marker)
}

// TestAPathWithACommaIsQuoted: a file name may hold a comma or a quote.
func TestAPathWithACommaIsQuoted(t *testing.T) {
	path := filepath.Join(t.TempDir(), "commit_files.csv")
	odd := []CommitFile{{"acme/app", commitFilesSHA, `docs/a,"b".md`}}
	if n, err := AppendCommitFiles(path, odd); err != nil || n != 1 {
		t.Fatalf("want 1 line written, got %d, %v", n, err)
	}
	wantLoaded(t, path, LoadCommitFiles, odd)
}

// TestACommitFileThatCannotBeStoredIsRefused: each broken field is refused,
// naming it.
func TestACommitFileThatCannotBeStoredIsRefused(t *testing.T) {
	for name, c := range map[string]struct {
		file CommitFile
		word string
	}{
		"repository": {CommitFile{"app", commitFilesSHA, "a.go"}, "repository"},
		"sha":        {CommitFile{"acme/app", "abc", "a.go"}, "sha"},
		"line break": {CommitFile{"acme/app", commitFilesSHA, "a\nb.go"}, "path"},
	} {
		t.Run(name, func(t *testing.T) {
			n, err := AppendCommitFiles(filepath.Join(t.TempDir(), "commit_files.csv"), []CommitFile{c.file})
			if n != 0 || !refusedFor(err, c.word) {
				t.Errorf("want %s refused, got %d, %v", c.word, n, err)
			}
		})
	}
}

// TestAMalformedCommitFilesFileIsRefusedOnRead: a line with a SHA that is
// none names its line.
func TestAMalformedCommitFilesFileIsRefusedOnRead(t *testing.T) {
	path := filepath.Join(t.TempDir(), "commit_files.csv")
	writeAt(t, path, commitFilesHead+"acme/app,"+strings.Repeat("g", 40)+",a.go\n")
	if _, err := LoadCommitFiles(path); !malformedOn(err, 3, "sha") {
		t.Errorf("want line 3 refused for sha, got %v", err)
	}
}
