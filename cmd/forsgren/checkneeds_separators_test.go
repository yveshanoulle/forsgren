package main

import (
	"strings"
	"testing"
)

// separatorConflict is the reason both items of a separator conflict give
// (forsgren#536, decision #537 A, forsgren#538).
const separatorConflict = "thousands_separator comma and decimal_separator comma are both the mark \",\"; " +
	"use different marks; both separators revert to their defaults, narrow_space and point"

// TestCheckNeedsReportsASeparatorConflictAsRefusedSettings (forsgren#536, #538):
// comma for both separators is two items under the refused settings heading,
// each naming its key, value, the conflict and the default in force, saying
// both separators reverted to their defaults; the run stays exit 0 and ok.
func TestCheckNeedsReportsASeparatorConflictAsRefusedSettings(t *testing.T) {
	fake := newRecordingIssueServer(t, "", "")
	installationWithIssuesWrite(t)
	configWith(t, "thousands_separator: comma", "decimal_separator: comma")
	code, status := runCheckNeeds(t)
	if code != 0 || status != statusOK {
		t.Errorf("want exit 0 and %q, got %d, %q", statusOK, code, status)
	}
	if len(fake.writes) != 1 {
		t.Fatalf("want one write, got %q", fake.writes)
	}
	wantInOrderIn(t, fake.writes[0], "## Refused settings",
		"- [ ] `thousands_separator`: `comma` is not accepted: "+separatorConflict+". Using the default `narrow_space`.",
		"- [ ] `decimal_separator`: `comma` is not accepted: "+separatorConflict+". Using the default `point`.")
	if strings.Contains(fake.writes[0], "## Missing requirements") {
		t.Errorf("want no missing requirements heading, got %q", fake.writes[0])
	}
}
