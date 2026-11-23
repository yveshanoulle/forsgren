package main

import (
	"io"
	"path/filepath"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
	"github.com/yveshanoulle/forsgren/internal/page"
)

// historyPageData is the page data of the history at data for cfg at the
// render time at: what pageData fills once it has read the history.
func historyPageData(t *testing.T, cfg config.Config, data string, at time.Time) page.Data {
	t.Helper()
	stored, err := loadHistory(cfg, data, io.Discard)
	if err != nil {
		t.Fatal(err)
	}
	got, err := withHistory(page.Data{}, cfg, stored, at)
	if err != nil {
		t.Fatal(err)
	}
	return got
}

// storedWithIssue7 is loadHistory of the acme history with data/issues.csv
// beside it holding the creation of issue 7, and the path of that history.
func storedWithIssue7(t *testing.T) (storedHistory, string) {
	t.Helper()
	data := writeHistory(t, acmeHistory())
	events := []history.IssueEvent{issueEventAt(7, "created", "", "2026-10-02T09:00:00Z")}
	if _, err := history.AppendIssueEvents(filepath.Join(filepath.Dir(data), "issues.csv"), events); err != nil {
		t.Fatal(err)
	}
	stored, err := loadHistory(config.Config{}, data, io.Discard)
	if err != nil {
		t.Fatal(err)
	}
	return stored, data
}

// TestLoadHistoryKeepsThePathAndTheDeployments: loadHistory keeps the path of
// the history, for the files withHistory reads beside it later, and its
// deployments as metrics data.
func TestLoadHistoryKeepsThePathAndTheDeployments(t *testing.T) {
	stored, data := storedWithIssue7(t)
	if stored.path != data {
		t.Errorf("want the path %q, got %q", data, stored.path)
	}
	if got, want := len(stored.metrics.Records), len(acmeHistory()); got != want {
		t.Errorf("want %d deployments, got %d", want, got)
	}
}

// TestLoadHistoryReadsTheIssuesBesideTheHistory: loadHistory carries the issue
// events of data/issues.csv beside the history, which withHistory turns into
// the rows of the days and issues pages.
func TestLoadHistoryReadsTheIssuesBesideTheHistory(t *testing.T) {
	stored, _ := storedWithIssue7(t)
	if len(stored.events) != 1 || stored.events[0].Issue != 7 {
		t.Errorf("want the one event of issue 7, got %+v", stored.events)
	}
}
