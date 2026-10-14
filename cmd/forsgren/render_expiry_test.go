package main

import (
	"path/filepath"
	"strings"
	"testing"
)

// tokenExpiryRow is the settings page's row for a token that expires on
// 2027-01-12 (forsgren#177).
const tokenExpiryRow = "          <tr>\n            <th scope=\"row\">Token expires</th>\n" +
	"            <td>2027-01-12</td>\n" +
	"            <td colspan=\"2\">FORSGREN_TOKEN, as GitHub reports it</td>\n          </tr>\n"

// settingsAfterRender renders with the arguments and returns the settings page.
func settingsAfterRender(t *testing.T, extra ...string) string {
	t.Helper()
	pinNow(t)
	dir := filepath.Join(t.TempDir(), "site")
	cfg := writeConfig(t, "version: 1\nprojects: []\n")
	args := append([]string{"render", "--out", dir, "--config", cfg}, extra...)
	if code, _, stderr := runCommand(args...); code != 0 {
		t.Fatalf("want exit 0, got %d (stderr %q)", code, stderr)
	}
	return readFile(t, filepath.Join(dir, "settings.html"))
}

// TestRenderShowsTheTokenExpiryOnTheSettingsPage (forsgren#177): with
// --token-expiry naming a file that holds an RFC 3339 date, the settings page
// has a Token expires row with that day in UTC.
func TestRenderShowsTheTokenExpiryOnTheSettingsPage(t *testing.T) {
	t.Chdir(t.TempDir())
	settings := settingsAfterRender(t, "--token-expiry", writeExpiry(t, "2027-01-12T23:35:47Z\n"))
	if !strings.Contains(settings, tokenExpiryRow) {
		t.Errorf("want the settings page to hold the row %q, got:\n%s", tokenExpiryRow, settings)
	}
}

// TestRenderShowsNoTokenExpiryRowWithoutAUsableDate (forsgren#177): no flag,
// a missing file, a directory and a file that is no date leave the row out.
func TestRenderShowsNoTokenExpiryRowWithoutAUsableDate(t *testing.T) {
	t.Chdir(t.TempDir())
	cases := map[string][]string{
		"no flag":    nil,
		"no file":    {"--token-expiry", "no-such-file"},
		"directory":  {"--token-expiry", "."},
		"not a date": {"--token-expiry", writeExpiry(t, "soon\n")},
	}
	for name, args := range cases {
		if settings := settingsAfterRender(t, args...); strings.Contains(settings, "Token expires") {
			t.Errorf("%s: want no Token expires row, got:\n%s", name, settings)
		}
	}
}
