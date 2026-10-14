package main

import (
	"os"
	"strings"
	"testing"
	"time"
)

// atFirstOfOctober fixes the clock of check-needs at 2026-10-01 for the test.
func atFirstOfOctober(t *testing.T) {
	t.Helper()
	old := now
	now = func() time.Time { return time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC) }
	t.Cleanup(func() { now = old })
}

// writeExpiry writes the expiry line collect would write into the checkout
// and returns the file's path.
func writeExpiry(t *testing.T, line string) string {
	t.Helper()
	if err := os.WriteFile("token-expiry", []byte(line), 0o600); err != nil {
		t.Fatal(err)
	}
	return "token-expiry"
}

// checkNeedsWithTokenExpiry runs check-needs for acme/data at 2026-10-01 in
// a checkout where every need of 0.4.0 is in place, --token-expiry naming the
// file expiry gives there.
func checkNeedsWithTokenExpiry(t *testing.T, expiry func(*testing.T) string) (int, string, string) {
	t.Helper()
	setVersion(t, "0.4.0")
	atFirstOfOctober(t)
	t.Setenv("GITHUB_TOKEN", testToken)
	installationWithIssuesWrite(t)
	return runCommand("check-needs", "--config", "forsgren.config.yml",
		"--repository", "acme/data", "--token-expiry", expiry(t))
}

// TestCheckNeedsMakesAnItemOfATokenThatExpiresSoon (forsgren#177): every
// need of 0.4.0 is in place, and the token expires within 14 days: the setup
// issue is created, its item naming the date and the command to set a new
// token.
func TestCheckNeedsMakesAnItemOfATokenThatExpiresSoon(t *testing.T) {
	t.Setenv("GITHUB_REPOSITORY", "acme/data")
	fake := newSetupServer(t, 201)
	code, stdout, stderr := checkNeedsWithTokenExpiry(t,
		func(t *testing.T) string { return writeExpiry(t, "2026-10-10T08:35:47Z\n") })
	const item = "FORSGREN_TOKEN expires on 2026-10-10. Make a new fine-grained token and set it " +
		"with `gh secret set FORSGREN_TOKEN -R acme/data` in a separate terminal."
	if code != 0 || !strings.Contains(stdout, item) || len(fake.posts) != 1 || !strings.Contains(fake.posts[0], item) {
		t.Errorf("want exit 0 and the item %q in stdout and the issue, got %d, %q, %q, %q",
			item, code, stdout, stderr, fake.posts)
	}
}

// TestCheckNeedsHasNoItemForATokenThatIsFarOrUnknown (forsgren#177): a far
// date, no file, a directory and a file that is no date are nothing missing,
// so the open setup issue is closed again (the fake refuses that write,
// which the note on stderr shows).
func TestCheckNeedsHasNoItemForATokenThatIsFarOrUnknown(t *testing.T) {
	cases := map[string]func(t *testing.T) string{
		"far":        func(t *testing.T) string { return writeExpiry(t, "2026-10-15T00:00:01Z\n") },
		"no file":    func(*testing.T) string { return "no-such-file" },
		"directory":  func(*testing.T) string { return "." },
		"not a date": func(t *testing.T) string { return writeExpiry(t, "soon\n") },
	}
	for name, file := range cases {
		t.Run(name, func(t *testing.T) {
			newOpenIssueServer(t)
			code, _, stderr := checkNeedsWithTokenExpiry(t, file)
			if code != 0 || !strings.Contains(stderr, "the setup issue could not be closed") {
				t.Errorf("want exit 0 and an attempt to close the issue, got %d, %q", code, stderr)
			}
		})
	}
}
