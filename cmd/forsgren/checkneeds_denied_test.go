package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
	"github.com/yveshanoulle/forsgren/internal/needs"
)

// The refused pull request reads in the setup issue (forsgren#321, step 2):
// check-needs reads data/pulls_denied.csv of the checkout (or --pulls-denied)
// and adds an item per refused repository, naming the token and its fix.

const (
	jobItem = "forsgren was refused the pull request read of acme/app with GITHUB_TOKEN, the job's token. " +
		"Add `pull-requests: read` to the `permissions:` of the forsgren job in .github/workflows/forsgren.yml."
	forsgrenItem = "forsgren was refused the pull request read of acme/app with FORSGREN_TOKEN. " +
		"Give FORSGREN_TOKEN the repository permission Pull requests: Read for acme/app."
	unnamedItem = "forsgren was refused the pull request read of acme/app; the file that notes it does not name the token."

	// noFile and emptiedFile are the token arguments of checkNeedsWithDenied
	// that write no pulls denied file, and one that lists no repository.
	noFile      = "no file"
	emptiedFile = "emptied file"
)

// checkNeedsWithDenied runs check-needs for acme/data in a checkout where
// every need of 0.4.0 is in place, with a pulls denied file at path (the
// default one for "") that lists acme/app refused with token, or noFile or
// emptiedFile; extra are more arguments.
func checkNeedsWithDenied(t *testing.T, token, path string, extra ...string) (int, string, string) {
	t.Helper()
	setVersion(t, "0.4.0")
	t.Setenv("GITHUB_TOKEN", testToken)
	installationWithIssuesWrite(t)
	if token != noFile {
		writePullsDeniedOf(t, token, path)
	}
	args := append([]string{"check-needs", "--config", "forsgren.config.yml", "--repository", "acme/data"}, extra...)
	return runCommand(args...)
}

// writePullsDeniedOf writes the pulls denied file at path (the default one
// for ""): acme/app refused with token, or no repository for emptiedFile.
func writePullsDeniedOf(t *testing.T, token, path string) {
	t.Helper()
	if path == "" {
		path = filepath.Join("data", "pulls_denied.csv")
	}
	denied := history.PullsDenied{}
	if token != emptiedFile {
		denied["acme/app"] = history.Denial{At: time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC), Token: token}
	}
	if err := history.SavePullsDenied(path, denied); err != nil {
		t.Fatal(err)
	}
}

// wantCreatedWith fails t unless the run created exactly one issue, whose
// body has item and not the token's value, and printed item.
func wantCreatedWith(t *testing.T, fake *setupServer, item, stdout string) {
	t.Helper()
	if !strings.Contains(stdout, item) {
		t.Errorf("want the item %q in stdout, got %q", item, stdout)
	}
	if len(fake.posts) != 1 {
		t.Fatalf("want one issue, got %q", fake.posts)
	}
	if !strings.Contains(fake.posts[0], item) {
		t.Errorf("want the item %q in the issue, got %q", item, fake.posts[0])
	}
	if strings.Contains(fake.posts[0], testToken) {
		t.Errorf("want no token value in the issue, got %q", fake.posts[0])
	}
}

// TestCheckNeedsMakesAnItemOfARefusedPullRequestRead: the setup issue is
// created with the item of the token that was refused, GITHUB_TOKEN's fix in
// the job's permissions, a fine-grained token's on the token, a v1 line's,
// which names no token, both. The token's value is nowhere.
func TestCheckNeedsMakesAnItemOfARefusedPullRequestRead(t *testing.T) {
	t.Setenv("GITHUB_REPOSITORY", "acme/data")
	for _, c := range []struct{ token, item string }{
		{"GITHUB_TOKEN", jobItem},
		{"FORSGREN_TOKEN", forsgrenItem},
		{"", unnamedItem},
	} {
		t.Run(c.token, func(t *testing.T) {
			fake := newSetupServer(t, 201)
			_, stdout, _ := checkNeedsWithDenied(t, c.token, "")
			wantCreatedWith(t, fake, c.item, stdout)
		})
	}
}

// TestCheckNeedsReadsThePullsDeniedFileItIsGiven: --pulls-denied names the
// file instead of data/pulls_denied.csv.
func TestCheckNeedsReadsThePullsDeniedFileItIsGiven(t *testing.T) {
	fake := newSetupServer(t, 201)
	_, stdout, _ := checkNeedsWithDenied(t, "GITHUB_TOKEN", "elsewhere.csv", "--pulls-denied", "elsewhere.csv")
	wantCreatedWith(t, fake, jobItem, stdout)
}

// TestCheckNeedsClosesTheSetupIssueOnceNoReadIsRefused: the open setup issue
// that carried the item is closed when the file no longer lists the
// repository: no file, or one a later read of acme/app emptied.
func TestCheckNeedsClosesTheSetupIssueOnceNoReadIsRefused(t *testing.T) {
	t.Setenv("GITHUB_REPOSITORY", "acme/data")
	for _, token := range []string{noFile, emptiedFile} {
		t.Run(token, func(t *testing.T) {
			fake := newRecordingIssueServer(t, "open", needs.Marker+"\n\n- [ ] "+jobItem)
			code, _, stderr := checkNeedsWithDenied(t, token, "")
			if code != 0 || stderr != "" {
				t.Errorf("want exit 0 and a quiet run, got %d, %q", code, stderr)
			}
			wantClosed(t, fake)
		})
	}
}

// wantClosed fails t unless the only writes are the comment and the closing
// of issue 7, with no item.
func wantClosed(t *testing.T, fake *recordingIssueServer) {
	t.Helper()
	if len(fake.writes) != 2 || !strings.HasPrefix(fake.writes[1], "PATCH /repos/acme/data/issues/7 ") {
		t.Errorf("want the comment and the closing of issue 7, got %q", fake.writes)
	}
	if strings.Contains(strings.Join(fake.writes, "\n"), "refused") {
		t.Errorf("want no item in the writes, got %q", fake.writes)
	}
}

// TestCheckNeedsNotesAPullsDeniedFileItCannotRead: a file in no known format
// is a note on stderr, never a failure, and makes no item.
func TestCheckNeedsNotesAPullsDeniedFileItCannotRead(t *testing.T) {
	fake := newSetupServer(t, 201)
	setVersion(t, "0.4.0")
	t.Setenv("GITHUB_TOKEN", testToken)
	installationWithIssuesWrite(t)
	if err := os.WriteFile("bad.csv", []byte("not a pulls denied file\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	code, _, stderr := runCommand("check-needs", "--config", "forsgren.config.yml",
		"--repository", "acme/data", "--pulls-denied", "bad.csv")
	if code != 0 || !strings.Contains(stderr, "the refused pull request reads are unknown") {
		t.Errorf("want exit 0 and a note, got %d, %q", code, stderr)
	}
	if len(fake.posts) != 0 {
		t.Errorf("want no issue, got %q", fake.posts)
	}
}
