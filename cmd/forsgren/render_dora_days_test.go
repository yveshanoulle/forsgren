package main

import (
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// doraHistory is acme/api's history for the window tests: one success long
// before any window, and one 45 days before renderNow.
func doraHistory() []history.Record {
	ok := history.StateSuccess
	return []history.Record{
		shipped(1, "acme/api", ok, "2025-12-01T12:00:00Z"),
		shipped(2, "acme/api", ok, "2026-08-19T12:00:00Z"),
	}
}

// numbersOf is the numbers view of Acme Shop's frequency cells with the
// config keys written before validConfig.
func numbersOf(t *testing.T, keys string) string {
	t.Helper()
	_, _, index := renderWith(t, "--config", writeConfig(t, "view: numbers\n"+keys+validConfig),
		"--data", writeHistory(t, doraHistory()))
	return index
}

// TestRenderCountsTheConfiguredWindow (forsgren#178): a deployment 45 days
// old is counted in the table with dora_days: 90 and not with the default 30.
func TestRenderCountsTheConfiguredWindow(t *testing.T) {
	pinNow(t)
	const counted = "<td>1</td>"
	thirty, ninety := numbersOf(t, ""), numbersOf(t, "dora_days: 90\n")
	if !strings.Contains(ninety, counted) || strings.Contains(thirty, counted) {
		t.Errorf("want the deployment counted over 90 days only\n--- 30 ---\n%s\n--- 90 ---\n%s", thirty, ninety)
	}
}

// TestRenderTreatsARejectedWindowAsTheDefault (forsgren#178, #183): a
// dora_days that is not accepted renders the 30 days of the default.
func TestRenderTreatsARejectedWindowAsTheDefault(t *testing.T) {
	pinNow(t)
	if got, want := numbersOf(t, "dora_days: 60\n"), numbersOf(t, ""); got != want {
		t.Errorf("want the default page for a rejected window\n--- got ---\n%s\n--- want ---\n%s", got, want)
	}
}
