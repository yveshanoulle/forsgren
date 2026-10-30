package main

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/metrics"
	"github.com/yveshanoulle/forsgren/internal/page"
)

// The push files mark reaches the metrics (forsgren#589, step 6), read beside
// the history like the other push marks: a missing file holds none, a bad one
// fails the render.

const pushFilesFilledH = "# forsgren push files filled v1\nrepository,filled_at\n"

// webDataRow is the Web service row of the Data page data of the history at
// data.
func webDataRow(t *testing.T, data string) metrics.DataRow {
	t.Helper()
	got, err := withHistory(page.Data{}, pathsProject(), data, renderNow)
	if err != nil {
		t.Fatal(err)
	}
	for _, r := range got.DataStarts.Rows {
		if r.Name == "Web" {
			return r
		}
	}
	t.Fatalf("want a Web row, got %+v", got.DataStarts.Rows)
	return metrics.DataRow{}
}

// TestRenderTakesTheMarkOffAServiceRowOnceItsPushedCommitsAreRead: without
// push_files_filled.csv the Web service's Commits says earlier data is not
// yet read; a line for its repository, in another case, takes that off.
func TestRenderTakesTheMarkOffAServiceRowOnceItsPushedCommitsAreRead(t *testing.T) {
	data := writeData(t, acmeHistory(), acmeCommits())
	writeFilesOf(t, data)
	if row := webDataRow(t, data); !row.Commits.Stored() || !row.Commits.Cut {
		t.Fatalf("want Web's commits marked without the push files mark, got %+v", row.Commits)
	}
	filled := pushFilesFilledH + "ACME/Api,2026-10-01T00:00:00Z\n"
	if err := os.WriteFile(filepath.Join(filepath.Dir(data), "push_files_filled.csv"), []byte(filled), 0o600); err != nil {
		t.Fatal(err)
	}
	if row := webDataRow(t, data); row.Commits.Cut {
		t.Errorf("want Web's commits not marked once acme/api is noted, got %+v", row.Commits)
	}
}

// TestRenderRefusesABadPushFilesFilledFile: an unknown-version or malformed
// push files filled file fails the render, naming it; never read as none.
func TestRenderRefusesABadPushFilesFilledFile(t *testing.T) {
	wantBadFileRefused(t, "push_files_filled.csv", map[string]badFile{
		"unknown version": {"# forsgren push files filled v2\n", "unknown history format version"},
		"malformed line":  {pushFilesFilledH + "acme/api\n", "line 3: malformed history"},
	})
}
