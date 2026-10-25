package main

import (
	"os"
	"path/filepath"
	"testing"
)

// pullsDeniedHead is the head of data/pulls_denied.csv, the pulls denied
// format v1 (forsgren#337), still read since forsgren#321.
const pullsDeniedHead = "# forsgren pulls denied v1\nrepository,denied_at\n"

// pullsDeniedHeadV2 is the head of the pulls denied format v2 (forsgren#321),
// which render reads as it reads v1.
const pullsDeniedHeadV2 = "# forsgren pulls denied v2\nrepository,denied_at,token\n"

// notReadableCell is the Mainline Lead Time cell of a project collect was
// refused the pull request read of (forsgren#337, step 2).
const notReadableCell = "Pull requests not readable"

// writePullsDenied writes lines, after the head, as data/pulls_denied.csv
// beside the history at data.
func writePullsDenied(t *testing.T, data, lines string) {
	t.Helper()
	path := filepath.Join(filepath.Dir(data), "pulls_denied.csv")
	if err := os.WriteFile(path, []byte(pullsDeniedHead+lines), 0o600); err != nil {
		t.Fatal(err)
	}
}

// TestRenderTbdPageSaysThePullRequestsAreNotReadable (forsgren#337, step 2):
// with data/pulls_denied.csv beside --data naming acme/api, written here as
// ACME/Api so the case does not count (decision #339), Acme Shop's Mainline
// Lead Time cell says the pull requests are not readable, though its other
// pull requests were read, and Acme Tools keeps its "-"; without pulls.csv,
// Acme Shop is still not readable and Acme Tools not collected yet. A
// missing pulls_denied.csv refuses nothing, which the other TBD tests show.
func TestRenderTbdPageSaysThePullRequestsAreNotReadable(t *testing.T) {
	pinNow(t)
	data := writeData(t, acmeHistory(), acmeCommits())
	writePullsDenied(t, data, "ACME/Api,2026-10-01T00:00:00Z\n")
	wantIn(t, tbdSiteOf(t, validConfig, data), leadRow(shopCell, notReadableCell),
		leadRow(noCells, "No pull requests have been collected yet"))
	writePulls(t, data, acmePulls(t))
	wantIn(t, tbdSiteOf(t, validConfig, data), leadRow(shopCell, notReadableCell),
		leadRow(noCells, noHumanPulls))
}

// TestRenderReadsAPullsDeniedFileOfFormatV2 (forsgren#321, step 1): the token
// column changes nothing on the page; the cell is the same as for v1.
func TestRenderReadsAPullsDeniedFileOfFormatV2(t *testing.T) {
	pinNow(t)
	data := writeData(t, acmeHistory(), acmeCommits())
	path := filepath.Join(filepath.Dir(data), "pulls_denied.csv")
	content := pullsDeniedHeadV2 + "acme/api,2026-10-01T00:00:00Z,FORSGREN_TOKEN\n"
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	wantIn(t, tbdSiteOf(t, validConfig, data), leadRow(shopCell, notReadableCell))
}

// TestRenderRefusesABadPullsDeniedFile (forsgren#337, step 2): a malformed
// or unknown-version pulls denied file fails render with its own message,
// naming it, and writes nothing, as the other data files do; it is never
// read as no refusal.
func TestRenderRefusesABadPullsDeniedFile(t *testing.T) {
	wantBadFileRefused(t, "pulls_denied.csv", map[string]badFile{
		"unknown version": {"# forsgren pulls denied v3\n", "unknown history format version"},
		"malformed line":  {pullsDeniedHead + "acme/api\n", "line 3: malformed history"},
		"a token's value": {pullsDeniedHeadV2 + "acme/api,2026-10-01T00:00:00Z,ghp_abc\n", "line 3: malformed history"},
	})
}
