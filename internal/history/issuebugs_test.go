package history

import (
	"os"
	"path/filepath"
	"slices"
	"testing"
)

// wantStored fails unless appending bugs to the file at path writes want lines.
func wantStored(t *testing.T, path string, bugs []IssueBug, want int) {
	t.Helper()
	if n, err := AppendIssueBugs(path, bugs); err != nil || n != want {
		t.Fatalf("want %d line(s) stored, got %d, %v", want, n, err)
	}
}

// TestAppendIssueBugsWritesAnIssueAgainOnlyWhenItsLabelChanged (forsgren#126):
// a new file gets the version line, the column line and one line per issue;
// a second call writes only the issue whose Bug changed, and LoadIssueBugs
// gives each issue as its newest line says, in the order they first appear.
func TestAppendIssueBugsWritesAnIssueAgainOnlyWhenItsLabelChanged(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data", "issue_bugs.csv")
	seven := IssueBug{Repository: "acme/app", Issue: 7, Bug: true}
	eight := IssueBug{Repository: "acme/app", Issue: 8, Bug: true}
	wantStored(t, path, []IssueBug{seven, eight}, 2)
	unlabelled := IssueBug{Repository: "ACME/app", Issue: 7, Bug: false}
	wantStored(t, path, []IssueBug{unlabelled, eight}, 1)
	want := "# forsgren issue bugs v1\n" +
		"repository,issue,bug\n" +
		"acme/app,7,true\n" +
		"acme/app,8,true\n" +
		"ACME/app,7,false\n"
	if got, _ := os.ReadFile(filepath.Clean(path)); string(got) != want {
		t.Errorf("want the file\n%s\ngot\n%s", want, got)
	}
	got, err := LoadIssueBugs(path)
	if err != nil || !slices.Equal(got, []IssueBug{unlabelled, eight}) {
		t.Errorf("want the newest line of each issue, got %v, %v", got, err)
	}
}
