package main

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/history"
	"github.com/yveshanoulle/forsgren/internal/metrics"
	"github.com/yveshanoulle/forsgren/internal/page"
)

// The commit files progress file reaches the Data page (forsgren#594, step 2),
// read beside the history: a missing file is no read going, a bad one fails
// the render.

const filesProgressH = "# forsgren commit files progress v1\nrepository,read,left\n"

// filesReadings are the Data page's reads still going of the history at data.
func filesReadings(t *testing.T, data string) []metrics.FilesReading {
	t.Helper()
	got, err := withHistory(page.Data{}, pathsProject(), data, renderNow)
	if err != nil {
		t.Fatal(err)
	}
	return got.FilesReadings
}

// TestRenderSaysHowFarAProjectsCommitFilesReadIs: without the file no project
// has a read going; with a line for its repository Acme Shop has, its runs
// left rounded up at the cap of a run, and a repository in no project is left
// out.
func TestRenderSaysHowFarAProjectsCommitFilesReadIs(t *testing.T) {
	data := writeData(t, acmeHistory(), acmeCommits())
	if got := filesReadings(t, data); len(got) != 0 {
		t.Fatalf("want no read going without the file, got %+v", got)
	}
	progress := filesProgressH + "acme/api,4199,3925\nacme/gone,1,1\n"
	if err := os.WriteFile(filepath.Join(filepath.Dir(data), "commit_files_progress.csv"),
		[]byte(progress), 0o600); err != nil {
		t.Fatal(err)
	}
	want := []metrics.FilesReading{
		{Project: "Acme Shop", FilesProgress: history.FilesProgress{Read: 4199, Left: 3925}, Runs: 4}}
	if got := filesReadings(t, data); !reflect.DeepEqual(got, want) {
		t.Errorf("want %+v, got %+v", want, got)
	}
}

// TestRenderRefusesABadCommitFilesProgressFile: an unknown-version or
// malformed progress file fails the render, naming it; never read as none.
func TestRenderRefusesABadCommitFilesProgressFile(t *testing.T) {
	wantBadFileRefused(t, "commit_files_progress.csv", map[string]badFile{
		"unknown version": {"# forsgren commit files progress v2\n", "unknown history format version"},
		"malformed line":  {filesProgressH + "acme/api,x,2\n", "line 3: malformed history"},
	})
}
