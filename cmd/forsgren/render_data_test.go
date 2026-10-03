package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// renderNow is the pinned render time of these tests.
var renderNow = time.Date(2026, 10, 3, 12, 0, 0, 0, time.UTC)

// The commit and task of every fixture record: neither may reach the page.
const (
	fixtureCommit = "c0ffee0123456789abcdef0123456789abcdef01"
	fixtureTask   = "task-name-stays-private"
)

// pinNow sets render's clock to renderNow for this test only.
func pinNow(t *testing.T) {
	t.Helper()
	old := now
	now = func() time.Time { return renderNow }
	t.Cleanup(func() { now = old })
}

// shipped is a record of repository in state, created at the UTC time at
// (2006-01-02T15:04:05Z), with a unique ID.
func shipped(id int64, repository string, state history.State, at string) history.Record {
	created, err := time.Parse(time.RFC3339, at)
	if err != nil {
		panic(err)
	}
	return history.Record{
		Project: "Acme Shop", Repository: repository, Kind: history.KindEnvironment, Name: "acme-live",
		ID: id, Commit: fixtureCommit, CreatedAt: created, State: state, Task: fixtureTask,
	}
}

// acmeHistory is validConfig's history at renderNow: Acme Shop has 3
// successes in the last 7 days (one exactly 7 days old), 12 in the last 30
// (one exactly 30 days old), the newest on 2026-10-01, and a newer failure
// and other; Acme Tools has a failure only; acme/gone is in no project.
func acmeHistory() []history.Record {
	ok := history.StateSuccess
	records := []history.Record{
		shipped(1, "acme/api", ok, "2026-10-01T09:30:00Z"),
		shipped(2, "acme/ios-app", ok, "2026-09-30T08:00:00Z"),
		shipped(3, "acme/api", ok, "2026-09-26T12:00:00Z"),
		shipped(4, "acme/api", ok, "2026-09-04T12:00:00Z"),
		shipped(5, "acme/api", ok, "2026-08-20T10:00:00Z"),
		shipped(6, "acme/api", history.StateFailure, "2026-10-02T10:00:00Z"),
		shipped(7, "acme/ios-app", history.StateOther, "2026-10-02T11:00:00Z"),
		shipped(8, "acme/cli", history.StateFailure, "2026-10-01T10:00:00Z"),
		shipped(9, "acme/gone", ok, "2026-10-02T10:00:00Z"),
	}
	for day := 10; day <= 17; day++ {
		at := time.Date(2026, 9, day, 15, 0, 0, 0, time.UTC).Format(time.RFC3339)
		records = append(records, shipped(int64(100+day), "acme/ios-app", ok, at))
	}
	return records
}

// writeHistory stores records as a history file and returns its path.
func writeHistory(t *testing.T, records []history.Record) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "data", "deployments.csv")
	if _, err := history.Append(path, records); err != nil {
		t.Fatal(err)
	}
	return path
}

// wantGolden renders with extra arguments and fails the test unless it
// exits 0 with the page of the golden file name.
func wantGolden(t *testing.T, golden string, extra ...string) string {
	t.Helper()
	code, stderr, index := renderWith(t, extra...)
	if code != 0 {
		t.Fatalf("want exit 0, got %d (stderr %q)", code, stderr)
	}
	if want := readFile(t, "../../internal/page/testdata/"+golden); index != want {
		t.Errorf("the page differs from %s\n--- got ---\n%s\n--- want ---\n%s", golden, index, want)
	}
	return index
}

// TestRenderShowsDeploymentFrequency (forsgren#12, step 7): with --config
// and --data the page shows each project's numbers, in config order. No
// commits file next to the history is no commit (forsgren#16, step 5): a
// project with deployments says "No lead time yet".
func TestRenderShowsDeploymentFrequency(t *testing.T) {
	pinNow(t)
	wantGolden(t, "index.frequency.golden.html",
		"--config", writeConfig(t, validConfig), "--data", writeHistory(t, acmeHistory()))
}

// TestRenderShowsNoRepositoryCommitOrTask: the page names projects, never a
// repository, an environment or workflow, a commit or a task.
func TestRenderShowsNoRepositoryCommitOrTask(t *testing.T) {
	pinNow(t)
	_, _, index := renderWith(t, "--config", writeConfig(t, validConfig), "--data", writeHistory(t, acmeHistory()))
	if !strings.Contains(index, "Acme Shop") {
		t.Fatalf("want the frequency page, got:\n%s", index)
	}
	for _, private := range []string{"acme/", "acme-live", "testflight", fixtureCommit[:7], fixtureTask} {
		if strings.Contains(index, private) {
			t.Errorf("the page shows %q:\n%s", private, index)
		}
	}
}

// TestRenderWithoutHistoryYet: a missing history file (a new install before
// its first collect) is an empty history, not an error.
func TestRenderWithoutHistoryYet(t *testing.T) {
	pinNow(t)
	missing := filepath.Join(t.TempDir(), "data", "deployments.csv")
	wantGolden(t, "index.no-data.golden.html", "--config", writeConfig(t, validConfig), "--data", missing)
}

// TestRenderWithNoProjectsAndData: zero projects keep the no-projects page.
func TestRenderWithNoProjectsAndData(t *testing.T) {
	pinNow(t)
	wantGolden(t, "index.no-projects.golden.html",
		"--config", writeConfig(t, "version: 1\nprojects: []\n"), "--data", writeHistory(t, acmeHistory()))
}

// TestRenderRefusesABadHistory: a malformed or unknown-version history fails
// render with the history's own message, and writes nothing.
func TestRenderRefusesABadHistory(t *testing.T) {
	head := "# forsgren history v1\nproject,repository,kind,name,deployment_id,commit,created_at,state,task\n"
	cases := map[string]struct{ content, want string }{
		"unknown version": {"# forsgren history v9\n", "unknown history format version"},
		"malformed line":  {head + "not,a,record\n", "line 3: malformed history"},
	}
	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "deployments.csv")
			if err := os.WriteFile(path, []byte(c.content), 0o600); err != nil {
				t.Fatal(err)
			}
			wantRefused(t, path, path, c.want)
		})
	}
}

// wantRefused renders validConfig with the history at data and fails the
// test unless render exits 1, writes no page and says `render: <path>: `
// with want in the message, path being the refused file.
func wantRefused(t *testing.T, data, path, want string) {
	t.Helper()
	code, stderr, index := renderWith(t, "--config", writeConfig(t, validConfig), "--data", data)
	if code != 1 || index != "" {
		t.Errorf("want exit 1 and no page, got %d, %q", code, stderr)
	}
	if prefix := "render: " + path + ": "; !strings.HasPrefix(stderr, prefix) || !strings.Contains(stderr, want) {
		t.Errorf("want `%s...%s`, got %q", prefix, want, stderr)
	}
}

// TestRenderDataNeedsConfig: --data alone is a usage error, and the usage
// lists --data.
func TestRenderDataNeedsConfig(t *testing.T) {
	code, _, stderr := runCommand("render", "--out", t.TempDir(), "--data", "deployments.csv")
	if code != 2 || !strings.Contains(stderr, "render: --data <path> needs --config <path>") {
		t.Errorf("want exit 2 and the reason, got %d, %q", code, stderr)
	}
	if _, _, stderr := runCommand(); !strings.Contains(stderr, "[--config <path>] [--data <path>]") {
		t.Errorf("want the usage to list render's --data, got %q", stderr)
	}
}

// TestRenderShowsTheMinuteOfTheCalculationInUTC (forsgren#28): the page of a
// render with data says when its numbers were calculated, to the minute, in
// UTC whatever zone the clock is in (here 01:19 on the 4th is still the 3rd
// in UTC), cut off (never rounded up) at the minute.
func TestRenderShowsTheMinuteOfTheCalculationInUTC(t *testing.T) {
	old := now
	zone := time.FixedZone("CEST", 2*60*60)
	now = func() time.Time { return time.Date(2026, 10, 4, 1, 19, 59, 0, zone) }
	t.Cleanup(func() { now = old })
	_, _, index := renderWith(t, "--config", writeConfig(t, validConfig), "--data", writeHistory(t, acmeHistory()))
	const want = "<p>Calculated 2026-10-03 23:19 UTC, counting back from that moment: "
	if !strings.Contains(index, want) {
		t.Errorf("want the line %q on the page, got:\n%s", want, index)
	}
}

// TestRenderShowsNoCalculationTimeWithoutNumbers (forsgren#28): a page with
// no numbers calculated (no --config, no --data, or no projects) shows no
// time, so the repository's own build stays byte-identical across renders.
func TestRenderShowsNoCalculationTimeWithoutNumbers(t *testing.T) {
	pinNow(t)
	noProjects := writeConfig(t, "version: 1\nprojects: []\n")
	cases := map[string][]string{
		"no --config":       nil,
		"config only":       {"--config", writeConfig(t, validConfig)},
		"no projects":       {"--config", noProjects},
		"no projects, data": {"--config", noProjects, "--data", writeHistory(t, acmeHistory())},
	}
	for name, extra := range cases {
		t.Run(name, func(t *testing.T) {
			_, _, index := renderWith(t, extra...)
			if strings.Contains(index, "Calculated") || strings.Contains(index, "12:00") {
				t.Errorf("want no calculation time on the page, got:\n%s", index)
			}
		})
	}
}
