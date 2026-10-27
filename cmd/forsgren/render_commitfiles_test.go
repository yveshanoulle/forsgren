package main

import (
	"path/filepath"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
	"github.com/yveshanoulle/forsgren/internal/metrics"
	"github.com/yveshanoulle/forsgren/internal/page"
)

// The commit files reach the metrics (forsgren#496, step 4), read beside the
// history like commits.csv: a missing file is none, a malformed one fails the
// render.

const commitFilesH = "# forsgren commit files v1\nrepository,sha,path\n"

// pathsProject is Acme Shop whose acme/api has the service fixtureTask,
// labelled Web, with the path api/.
func pathsProject() config.Config {
	return config.Config{Projects: []config.Project{{Name: "Acme Shop", Repositories: []config.Repository{{
		Name:     "acme/api",
		Services: map[string]string{fixtureTask: "Web"},
		Paths:    map[string][]string{fixtureTask: {"api/"}},
	}}}}}
}

// writeFilesOf stores, beside the history at data, the files of the first
// commits of acmeCommits: the first changes api/x.go, the second web/y.go,
// the third (deployment 3) api/z.go.
func writeFilesOf(t *testing.T, data string) {
	t.Helper()
	commits := acmeCommits()
	file := func(c history.Commit, path string) history.CommitFile {
		return history.CommitFile{Repository: c.Repository, SHA: c.SHA, Path: path}
	}
	files := []history.CommitFile{file(commits[0], "api/x.go"), file(commits[1], "web/y.go"), file(commits[2], "api/z.go")}
	if _, err := history.AppendCommitFiles(filepath.Join(filepath.Dir(data), "commit_files.csv"), files); err != nil {
		t.Fatal(err)
	}
}

// webRow is the Web service row of the TBD page data of the history at data.
func webRow(t *testing.T, data string) metrics.TbdRow {
	t.Helper()
	got, err := withHistory(page.Data{}, pathsProject(), data, renderNow)
	if err != nil {
		t.Fatal(err)
	}
	for _, r := range got.TbdMetrics {
		if r.Name == "Web" {
			return r
		}
	}
	t.Fatalf("want a Web row, got %+v", got.TbdMetrics)
	return metrics.TbdRow{}
}

// TestRenderReadsTheCommitFilesBesideTheHistory: with commit_files.csv beside
// --data, the Web service counts the two commits that touch api/ (not the one
// that changes web/y.go) and has nothing left to read.
func TestRenderReadsTheCommitFilesBesideTheHistory(t *testing.T) {
	data := writeData(t, acmeHistory(), acmeCommits())
	writeFilesOf(t, data)
	row := webRow(t, data)
	if row.Deploy.Commits != 2 || row.FilesReading || row.DeployPerRepository {
		t.Errorf("want 2 commits timed and the files read, got %d (reading %v, per repository %v)",
			row.Deploy.Commits, row.FilesReading, row.DeployPerRepository)
	}
}

// TestRenderTakesAMissingCommitFilesFileAsNone: without commit_files.csv no
// commit of the Web service is read yet.
func TestRenderTakesAMissingCommitFilesFileAsNone(t *testing.T) {
	row := webRow(t, writeData(t, acmeHistory(), acmeCommits()))
	if row.Deploy.Commits != 0 || !row.FilesReading {
		t.Errorf("want no commit timed and the files still being read, got %d (reading %v)",
			row.Deploy.Commits, row.FilesReading)
	}
}

// TestRenderRefusesABadCommitFilesFile: a malformed or unknown-version commit
// files file fails render with its own message, naming it; never read as none.
func TestRenderRefusesABadCommitFilesFile(t *testing.T) {
	wantBadFileRefused(t, "commit_files.csv", map[string]badFile{
		"unknown version": {"# forsgren commit files v2\n", "unknown history format version"},
		"malformed line":  {commitFilesH + "acme/api,x\n", "line 3: malformed history"},
	})
}
