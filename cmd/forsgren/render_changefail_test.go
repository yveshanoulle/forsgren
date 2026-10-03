package main

import (
	"path/filepath"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// filedAt is a failure issue of repository opened at the UTC time at
// (2006-01-02T15:04:05Z).
func filedAt(repository string, number int64, at string) history.Failure {
	opened, err := time.Parse(time.RFC3339, at)
	if err != nil {
		panic(err)
	}
	return history.Failure{Repository: repository, Issue: number, OpenedAt: opened}
}

// acmeFailures are failure issues at renderNow: one of acme/api, which
// also has a failed deployment in the last 30 days, and one of
// acme/ios-app, which has none; one older than 30 days and one of
// acme/gone, in no project, do not count.
func acmeFailures() []history.Failure {
	return []history.Failure{
		filedAt("acme/api", 41, "2026-10-02T10:30:00Z"),
		filedAt("acme/ios-app", 7, "2026-09-30T09:00:00Z"),
		filedAt("acme/ios-app", 3, "2026-08-01T09:00:00Z"),
		filedAt("acme/gone", 1, "2026-10-02T09:00:00Z"),
	}
}

// writeFailures stores failures as the failures file next to the history
// at data.
func writeFailures(t *testing.T, data string, failures []history.Failure) {
	t.Helper()
	if _, err := history.AppendFailures(filepath.Join(filepath.Dir(data), "failures.csv"), failures); err != nil {
		t.Fatal(err)
	}
}

// TestRenderShowsChangeFailRate (forsgren#18, step 5): with
// data/failures.csv next to --data, each project's section shows its change
// fail rate. Acme Shop's 13 final deployments of the last 30 days hold 1
// failure, of acme/api; acme/api's failure issue is taken to be about it
// and acme/ios-app's issue is a second failed change: 2 of 13, 15%, the
// band 20%.
func TestRenderShowsChangeFailRate(t *testing.T) {
	pinNow(t)
	data := writeHistory(t, acmeHistory())
	writeFailures(t, data, acmeFailures())
	wantGolden(t, "index.changefail.golden.html", "--config", writeConfig(t, validConfig), "--data", data)
}

// TestRenderRefusesABadFailuresFile: a malformed or unknown-version
// failures file fails render with its own message, naming it, and writes
// nothing.
func TestRenderRefusesABadFailuresFile(t *testing.T) {
	head := "# forsgren failures v1\nrepository,issue,opened_at,closed_at,failure_start\n"
	wantBadFileRefused(t, "failures.csv", map[string]badFile{
		"unknown version": {"# forsgren failures v2\n", "unknown history format version"},
		"malformed line":  {head + "acme/api,41\n", "line 3: malformed history"},
	})
}
