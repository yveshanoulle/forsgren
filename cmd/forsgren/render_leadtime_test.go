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
		"--config", writeAllPagesConfig(t, validConfig), "--data", writeData(t, acmeHistory(), acmeCommits()))
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
	_, _, index := renderWith(t, "--config", writeAllPagesConfig(t, validConfig),
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

// authorLogin is the made-up GitHub login of every fixture commit of
// TestRenderShowsNoCommitAuthor: it may reach no page.
const authorLogin = "acme-dev-login"

// TestRenderShowsNoCommitAuthor (forsgren#273, decision 274): the commits
// file holds each commit's GitHub login, and no page of the site shows one,
// the TBD page's Developers column included: it counts these logins (Acme
// Shop's three commits in the window are one developer), so the cell the
// login would reach is on the page.
func TestRenderShowsNoCommitAuthor(t *testing.T) {
	pinNow(t)
	commits := acmeCommits()
	for i := range commits {
		commits[i].Author = authorLogin
	}
	data := writeData(t, acmeHistory(), commits)
	if stored := readFile(t, filepath.Join(filepath.Dir(data), "commits.csv")); !strings.Contains(stored, authorLogin) {
		t.Fatalf("want the login in the commits file, got:\n%s", stored)
	}
	site := renderSite(t, "--config", writeAllPagesConfig(t, validConfig), "--data", data)
	shopDevelopers := uncollected(leadRow(shopCell, "No pull requests have been collected yet")) + "            <td>1</td>"
	if got := readSite(t, site, "tbd.html"); !strings.Contains(got, shopDevelopers) {
		t.Errorf("want Acme Shop's Developers counted from the logins, got:\n%s", got)
	}
	wantNoPageShows(t, site, authorLogin)
}

// renderSite renders with extra arguments into a new directory and returns
// it, failing the test unless render exits 0.
func renderSite(t *testing.T, extra ...string) string {
	t.Helper()
	dir := filepath.Join(t.TempDir(), "site")
	if code, _, stderr := runCommand(append([]string{"render", "--out", dir}, extra...)...); code != 0 {
		t.Fatalf("want render to exit 0, got %d: %s", code, stderr)
	}
	return dir
}

// wantNoPageShows fails the test for every file of the site in dir that
// holds private.
func wantNoPageShows(t *testing.T, dir, private string) {
	t.Helper()
	err := filepath.WalkDir(dir, func(path string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return err
		}
		if strings.Contains(readFile(t, path), private) {
			t.Errorf("%s shows %q", path, private)
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
}

// TestRenderReadsAV1CommitsFile (forsgren#273): a commits file written before
// the author column, as an installation that has not collected since holds,
// still gives the lead time.
func TestRenderReadsAV1CommitsFile(t *testing.T) {
	pinNow(t)
	data := writeHistory(t, acmeHistory())
	lines := "# forsgren commits v1\nrepository,kind,deployment_id,commit,authored_at,deployed_at\n"
	for _, c := range acmeCommits() {
		lines += fmt.Sprintf("%s,%s,%d,%s,%s,%s\n", c.Repository, c.Kind, c.DeploymentID, c.SHA,
			c.AuthoredAt.Format(time.RFC3339), c.DeployedAt.Format(time.RFC3339))
	}
	if err := os.WriteFile(filepath.Join(filepath.Dir(data), "commits.csv"), []byte(lines), 0o600); err != nil {
		t.Fatal(err)
	}
	_, stderr, index := renderWith(t, "--config", writeAllPagesConfig(t, validConfig), "--data", data)
	if !strings.Contains(index, "Less than one hour · 17 min (3)") {
		t.Errorf("want the lead time from the v1 file, got %s:\n%s", stderr, index)
	}
}
