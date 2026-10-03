package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// shaPrefix starts the SHA of every fixture commit: no part of one may reach
// the page.
const shaPrefix = "c0ffee"

// shippedWith is a fixture commit of the deployment id of repository,
// created at deployed, authored at authored (both UTC,
// 2006-01-02T15:04:05Z). Its SHA is made from its author date, unique in
// each fixture.
func shippedWith(repository string, id int64, authored, deployed string) history.Commit {
	at := func(s string) time.Time {
		t, err := time.Parse(time.RFC3339, s)
		if err != nil {
			panic(err)
		}
		return t
	}
	return history.Commit{
		Repository: repository, Kind: history.KindEnvironment, DeploymentID: id,
		SHA:        fmt.Sprintf("%s%034x", shaPrefix, at(authored).Unix()),
		AuthoredAt: at(authored), DeployedAt: at(deployed),
	}
}

// acmeCommits are the commits of acmeHistory's deployments at renderNow.
// Acme Shop has 3 in the last 30 days: 17 minutes, 24 hours (its repository
// written in another case) and one authored after its deployment, which
// counts as 0; its median is 17 minutes. A commit of a deployment older than
// 30 days and one of acme/gone, in no project, do not count.
func acmeCommits() []history.Commit {
	return []history.Commit{
		shippedWith("acme/api", 1, "2026-10-01T09:13:00Z", "2026-10-01T09:30:00Z"),
		shippedWith("acme/api", 1, "2026-10-01T09:35:00Z", "2026-10-01T09:30:00Z"),
		shippedWith("Acme/API", 3, "2026-09-25T12:00:00Z", "2026-09-26T12:00:00Z"),
		shippedWith("acme/api", 5, "2026-08-19T10:00:00Z", "2026-08-20T10:00:00Z"),
		shippedWith("acme/gone", 9, "2026-10-02T09:59:00Z", "2026-10-02T10:00:00Z"),
	}
}

// writeData stores records as a history file and commits as the commits
// file next to it, and returns the history's path.
func writeData(t *testing.T, records []history.Record, commits []history.Commit) string {
	t.Helper()
	path := writeHistory(t, records)
	if _, err := history.AppendCommits(filepath.Join(filepath.Dir(path), "commits.csv"), commits); err != nil {
		t.Fatal(err)
	}
	return path
}

// TestRenderShowsLeadTime (forsgren#16, step 5): with data/commits.csv next
// to --data, each project's section shows its lead time for changes.
func TestRenderShowsLeadTime(t *testing.T) {
	pinNow(t)
	wantGolden(t, "index.leadtime.golden.html",
		"--config", writeConfig(t, validConfig), "--data", writeData(t, acmeHistory(), acmeCommits()))
}

// TestRenderRefusesABadCommitsFile: a malformed or unknown-version commits
// file fails render with its own message, naming it, and writes nothing.
func TestRenderRefusesABadCommitsFile(t *testing.T) {
	head := "# forsgren commits v1\nrepository,kind,deployment_id,commit,authored_at,deployed_at\n"
	wantBadFileRefused(t, "commits.csv", map[string]badFile{
		"unknown version": {"# forsgren commits v9\n", "unknown history format version"},
		"malformed line":  {head + "not,a,commit\n", "line 3: malformed history"},
	})
}

// badFile is a file next to the history that render must refuse: its
// content, and what render's error says.
type badFile struct{ content, want string }

// wantBadFileRefused writes each case's content as the file name next to a
// history, and fails the test unless render refuses it, naming it.
func wantBadFileRefused(t *testing.T, name string, cases map[string]badFile) {
	t.Helper()
	for caseName, c := range cases {
		t.Run(caseName, func(t *testing.T) {
			data := writeHistory(t, acmeHistory())
			file := filepath.Join(filepath.Dir(data), name)
			if err := os.WriteFile(file, []byte(c.content), 0o600); err != nil {
				t.Fatal(err)
			}
			wantRefused(t, data, file, c.want)
		})
	}
}

// TestRenderShowsNoCommitSHA: no part of a stored commit's SHA reaches the
// page, nor its repository.
func TestRenderShowsNoCommitSHA(t *testing.T) {
	pinNow(t)
	_, _, index := renderWith(t, "--config", writeConfig(t, validConfig),
		"--data", writeData(t, acmeHistory(), acmeCommits()))
	if !strings.Contains(index, "Less than one hour · 17 min (3)") {
		t.Fatalf("want the lead-time page, got:\n%s", index)
	}
	for _, private := range []string{shaPrefix, "acme/", "Acme/API"} {
		if strings.Contains(index, private) {
			t.Errorf("the page shows %q:\n%s", private, index)
		}
	}
}
