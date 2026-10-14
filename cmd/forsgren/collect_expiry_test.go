package main

import (
	"errors"
	"io/fs"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/github"
)

// expiryFile is the file --token-expiry names, in a fresh directory.
func expiryFile(t *testing.T) string { return filepath.Join(t.TempDir(), "token-expiry") }

// expiryHeader is an answer header that names value as the token's expiry
// date, as GitHub writes it; no header at all for "".
func expiryHeader(value string) http.Header {
	header := http.Header{}
	if value != "" {
		header.Set("GitHub-Authentication-Token-Expiration", value)
	}
	return header
}

// collectOneRepository runs collect on oneRepository with a fresh history,
// and the extra arguments.
func collectOneRepository(t *testing.T, extra ...string) outcome {
	t.Helper()
	args := []string{"--config", writeConfig(t, oneRepository), "--data", dataPath(t)}
	return collectRun(append(args, extra...)...)
}

// TestCollectWritesTheTokenExpiryToTheFile (forsgren#177): with
// --token-expiry, the date GitHub's header names is written to the file as
// one UTC RFC 3339 line, for the check-needs step to read.
func TestCollectWritesTheTokenExpiryToTheFile(t *testing.T) {
	t.Setenv("FORSGREN_TOKEN", testToken)
	fakeAPIWithHeader(t, acmeApp, 0, expiryHeader("2027-01-12 08:35:47 UTC"))
	file := expiryFile(t)
	got := collectOneRepository(t, "--token-expiry", file)
	if got.code != 0 {
		t.Fatalf("want exit 0, got %+v", got)
	}
	content, err := os.ReadFile(filepath.Clean(file))
	if err != nil || string(content) != "2027-01-12T08:35:47Z\n" {
		t.Errorf("want the expiry line, got %q (%v)", content, err)
	}
}

// TestCollectRemovesTheTokenExpiryFileWhenNoExpiryIsKnown (forsgren#177): an
// answer without the header (route A, a token that never expires) leaves no
// file, and takes a stale one away.
func TestCollectRemovesTheTokenExpiryFileWhenNoExpiryIsKnown(t *testing.T) {
	t.Setenv("FORSGREN_TOKEN", testToken)
	fakeAPI(t, acmeApp, 0)
	file := expiryFile(t)
	if err := os.WriteFile(file, []byte("2020-01-01T00:00:00Z\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	got := collectOneRepository(t, "--token-expiry", file)
	if _, err := os.Stat(file); got.code != 0 || !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("want exit 0 and no file, got %+v and %v", got, err)
	}
}

// TestCollectFailsWhenTheTokenExpiryFileCannotBeWritten (forsgren#177): a
// file that cannot be written, or a stale one that cannot be removed, is
// exit 1 with collect's own message, not silence.
func TestCollectFailsWhenTheTokenExpiryFileCannotBeWritten(t *testing.T) {
	t.Setenv("FORSGREN_TOKEN", testToken)
	cases := map[string]struct {
		header http.Header
		path   string
	}{
		"write":  {expiryHeader("2027-01-12 08:35:47 UTC"), filepath.Join(t.TempDir(), "missing", "token-expiry")},
		"remove": {nil, nonEmptyDir(t)},
	}
	for name, c := range cases {
		fakeAPIWithHeader(t, acmeApp, 0, c.header)
		got := collectOneRepository(t, "--token-expiry", c.path)
		if got.code != 1 || !strings.HasPrefix(got.stderr, "collect: ") {
			t.Errorf("%s: want exit 1 and collect's message, got %+v", name, got)
		}
	}
}

// nonEmptyDir is a directory that os.Remove cannot remove.
func nonEmptyDir(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "x"), nil, 0o600); err != nil {
		t.Fatal(err)
	}
	return dir
}

// TestCollectWarnsOnStderrWhenTheTokenExpiresWithin14Days (forsgren#177): the
// fake clock is 2026-10-01. An expiry up to 14 days away, or already past,
// is a warning with the date and the command to set a new token, and the
// exit code stays 0; a date further away, or none, is no warning.
func TestCollectWarnsOnStderrWhenTheTokenExpiresWithin14Days(t *testing.T) {
	t.Setenv("FORSGREN_TOKEN", testToken)
	t.Setenv("GITHUB_REPOSITORY", "")
	const tail = " Make a new fine-grained token and set it with " +
		"`gh secret set FORSGREN_TOKEN -R this installation's repository` in a separate terminal.\n"
	cases := []struct{ name, value, want string }{
		{"near", "2026-10-10 08:35:47 UTC", "collect: warning: FORSGREN_TOKEN expires on 2026-10-10." + tail},
		{"edge", "2026-10-15 00:00:00 UTC", "collect: warning: FORSGREN_TOKEN expires on 2026-10-15." + tail},
		{"past", "2026-09-30 08:35:47 UTC", "collect: warning: FORSGREN_TOKEN has expired on 2026-09-30." + tail},
		{"far", "2026-10-15 00:00:01 UTC", ""},
		{"none", "", ""},
	}
	for _, c := range cases {
		fakeAPIWithHeader(t, acmeApp, 0, expiryHeader(c.value))
		got := collectOneRepository(t, "--token-expiry", expiryFile(t))
		if got.code != 0 || got.stderr != c.want {
			t.Errorf("%s: want exit 0 and stderr %q, got %+v", c.name, c.want, got)
		}
	}
}

// TestTheTokenExpiryWarningNamesTheRepositoryTheWorkflowRunsIn (forsgren#177).
func TestTheTokenExpiryWarningNamesTheRepositoryTheWorkflowRunsIn(t *testing.T) {
	t.Setenv("FORSGREN_TOKEN", testToken)
	t.Setenv("GITHUB_REPOSITORY", "acme/shop")
	fakeAPIWithHeader(t, acmeApp, 0, expiryHeader("2026-10-10 00:00:00 UTC"))
	got := collectOneRepository(t)
	if !strings.Contains(got.stderr, "-R acme/shop`") {
		t.Errorf("want the repository in the command, got %q", got.stderr)
	}
}

// TestCollectNotesAnUnreadableExpiryHeaderOnce (forsgren#177): a header that
// is not a date is one note on stderr naming the first value, however many
// answers carried it; the run's exit code and the expiry file are not
// touched (no file without a valid date).
func TestCollectNotesAnUnreadableExpiryHeaderOnce(t *testing.T) {
	t.Setenv("FORSGREN_TOKEN", testToken)
	fakeAPIWithHeader(t, acmeApp, 0, expiryHeader("soon"))
	file := expiryFile(t)
	got := collectOneRepository(t, "--token-expiry", file)
	const note = "collect: note: GitHub sent an expiry header forsgren cannot read: \"soon\"\n"
	if got.code != 0 || got.stderr != note {
		t.Errorf("want exit 0 and exactly one note %q, got %+v", note, got)
	}
	if _, err := os.Stat(file); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("want no expiry file, got %v", err)
	}
}

// staleExpiry writes an expiry line from an earlier run and returns its path.
func staleExpiry(t *testing.T) string {
	t.Helper()
	file := expiryFile(t)
	if err := os.WriteFile(file, []byte("2026-10-10T08:35:47Z\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	return file
}

// TestAFailedCollectLeavesNoTokenExpiryFile (forsgren#177): the file is
// removed before anything else, so a collect that fails early (no token, an
// unreadable config) or whose requests are refused leaves none: check-needs
// then reads unknown, never an old run's date.
func TestAFailedCollectLeavesNoTokenExpiryFile(t *testing.T) {
	cases := map[string]func(t *testing.T) []string{
		"no token": func(t *testing.T) []string {
			t.Setenv("FORSGREN_TOKEN", "")
			return nil
		},
		"unreadable config": func(t *testing.T) []string {
			t.Setenv("FORSGREN_TOKEN", testToken)
			return []string{"--config", "no-such-config.yml", "--data", dataPath(t)}
		},
		"token refused": func(t *testing.T) []string {
			t.Setenv("FORSGREN_TOKEN", testToken)
			fakeAPI(t, acmeApp, http.StatusUnauthorized)
			return nil
		},
	}
	for name, setup := range cases {
		t.Run(name, func(t *testing.T) {
			file := staleExpiry(t)
			args := setup(t)
			if args == nil {
				args = []string{"--config", writeConfig(t, oneRepository), "--data", dataPath(t)}
			}
			got := collectRun(append(args, "--token-expiry", file)...)
			if _, err := os.Stat(file); got.code != 1 || !errors.Is(err, fs.ErrNotExist) {
				t.Errorf("want exit 1 and no file, got %+v and %v", got, err)
			}
		})
	}
}

// clientWithExpiry is the installation's client after one answer that named
// the expiry 2027-01-12 08:35:47 UTC.
func clientWithExpiry(t *testing.T) *github.Client {
	t.Helper()
	t.Setenv("FORSGREN_TOKEN", testToken)
	fakeAPIWithHeader(t, map[string]string{"/repos/acme/app": `{"default_branch":"main"}`}, 0,
		expiryHeader("2027-01-12 08:35:47 UTC"))
	client, err := githubClient()
	if err != nil {
		t.Fatal(err)
	}
	if _, err := client.DefaultBranch(t.Context(), "acme/app"); err != nil {
		t.Fatal(err)
	}
	return client
}

// TestTheTokenExpiryFileIsWrittenWhole (forsgren#177): the line is written
// beside the file and renamed over it: what is seen is the whole line, and no
// temporary file stays behind.
func TestTheTokenExpiryFileIsWrittenWhole(t *testing.T) {
	client := clientWithExpiry(t)
	file := expiryFile(t)
	if err := writeTokenExpiry(file, client); err != nil {
		t.Fatal(err)
	}
	if content, err := os.ReadFile(filepath.Clean(file)); err != nil || string(content) != "2027-01-12T08:35:47Z\n" {
		t.Errorf("want the expiry line, got %q (%v)", content, err)
	}
	if _, err := os.Stat(file + ".tmp"); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("want no temporary file after the write, got %v", err)
	}
}

// TestAFailedRenameLeavesNoTemporaryFile (forsgren#177): when the line cannot
// be renamed over the path (it is a directory with something in it), the
// error is returned, no temporary file stays behind and the path is as it was.
func TestAFailedRenameLeavesNoTemporaryFile(t *testing.T) {
	dir := nonEmptyDir(t)
	if err := writeTokenExpiry(dir, clientWithExpiry(t)); err == nil {
		t.Error("want an error for a path that is a directory")
	}
	if _, err := os.Stat(dir + ".tmp"); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("want no temporary file after the failed rename, got %v", err)
	}
	if _, err := os.Stat(filepath.Join(dir, "x")); err != nil {
		t.Errorf("want the directory as it was, got %v", err)
	}
}
