package main

import (
	"testing"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// TestRenderShowsWeekendDeployments (forsgren#115): the deployment
// frequency cell of a row with successes on a UTC Saturday or Sunday in the
// last 30 days says how many, "· 2 at weekends". acme/api has four
// successes, on Friday 2 October, Saturday 26 and Sunday 27 September and
// Monday 28 September, and a failure on Saturday 19 September; acme/ios-app
// has one success on a Wednesday.
func TestRenderShowsWeekendDeployments(t *testing.T) {
	pinNow(t)
	ok := history.StateSuccess
	records := []history.Record{
		shipped(1, "acme/api", ok, "2026-10-02T09:00:00Z"),
		shipped(2, "acme/api", ok, "2026-09-26T12:00:00Z"),
		shipped(3, "acme/api", ok, "2026-09-27T12:00:00Z"),
		shipped(4, "acme/api", ok, "2026-09-28T09:00:00Z"),
		shipped(5, "acme/api", history.StateFailure, "2026-09-19T12:00:00Z"),
		shipped(6, "acme/ios-app", ok, "2026-09-30T08:00:00Z"),
	}
	wantGolden(t, "index.weekend.golden.html",
		"--config", writeConfig(t, validConfig+daysOn), "--data", writeHistory(t, records))
}
