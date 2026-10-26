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

// The refused pull request and push reads in the setup issue (forsgren#321,
// step 2, and forsgren#414): check-needs reads data/pulls_denied.csv and
// data/pushes_denied.csv of the checkout (or --pulls-denied, --pushes-denied)
// and adds an item per refused repository, naming the token and its fix.

const (
	jobFixText = " the `permissions:` of the forsgren job in .github/workflows/forsgren.yml."
	unnamedEnd = "; the file that notes it does not name the token."

	// noFile and emptiedFile are the token arguments of checkNeedsWithDenied
	// that write no denied file, and one that lists no repository.
	noFile      = "no file"
	emptiedFile = "emptied file"
)

// refusedRead is one of the two reads whose refusals the setup issue lists:
// the file collect noted them in, the flag that names it and the items.
type refusedRead struct {
	noun, flag, file string
	save             func(string, history.Denied) error
	job, forsgren    string // the items of GITHUB_TOKEN and of FORSGREN_TOKEN
}

// unnamed is the item of a v1 line, which names no token.
func (r refusedRead) unnamed() string {
	return "forsgren was refused the " + r.noun + " read of acme/app" + unnamedEnd
}

var refusedReads = []refusedRead{
	{"pull request", "--pulls-denied", "pulls_denied.csv", history.SavePullsDenied,
		"forsgren was refused the pull request read of acme/app with GITHUB_TOKEN, the job's token. " +
			"Add `pull-requests: read` to" + jobFixText,
		"forsgren was refused the pull request read of acme/app with FORSGREN_TOKEN. " +
			"Give FORSGREN_TOKEN the repository permission Pull requests: Read for acme/app."},
	{"push", "--pushes-denied", "pushes_denied.csv", history.SavePushesDenied,
		"forsgren was refused the push read of acme/app with GITHUB_TOKEN, the job's token. " +
			"Add `contents: read` to" + jobFixText,
		"forsgren was refused the push read of acme/app with FORSGREN_TOKEN. " +
			"Give FORSGREN_TOKEN the repository permission Contents: Read for acme/app."},
}

// eachRefusedRead runs check as a subtest of every kind of read.
func eachRefusedRead(t *testing.T, check func(*testing.T, refusedRead)) {
	t.Helper()
	for _, r := range refusedReads {
		t.Run(r.noun, func(t *testing.T) { check(t, r) })
	}
}

// checkNeedsWithDenied runs check-needs for acme/data in a checkout where
// every need of 0.4.0 is in place, with a denied file of r at path (the
// default one for "") that lists acme/app refused with token, or noFile or
// emptiedFile; extra are more arguments.
func checkNeedsWithDenied(t *testing.T, r refusedRead, token, path string, extra ...string) (int, string, string) {
	t.Helper()
	setVersion(t, "0.4.0")
	t.Setenv("GITHUB_TOKEN", testToken)
	installationWithIssuesWrite(t)
	if token != noFile {
		writeDeniedOf(t, r, token, path)
	}
	args := append([]string{"check-needs", "--config", "forsgren.config.yml", "--repository", "acme/data"}, extra...)
	return runCommand(args...)
}

// writeDeniedOf writes r's denied file at path (the default one for ""):
// acme/app refused with token, or no repository for emptiedFile.
func writeDeniedOf(t *testing.T, r refusedRead, token, path string) {
	t.Helper()
	if path == "" {
		path = filepath.Join("data", r.file)
	}
	denied := history.Denied{}
	if token != emptiedFile {
		denied["acme/app"] = history.Denial{At: time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC), Token: token}
	}
	if err := r.save(path, denied); err != nil {
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

// TestCheckNeedsMakesAnItemOfARefusedRead: the setup issue is created with
// the item of the token that was refused, GITHUB_TOKEN's fix in the job's
// permissions, a fine-grained token's on the token, a v1 line's, which names
// no token, both. The token's value is nowhere.
func TestCheckNeedsMakesAnItemOfARefusedRead(t *testing.T) {
	t.Setenv("GITHUB_REPOSITORY", "acme/data")
	eachRefusedRead(t, func(t *testing.T, r refusedRead) {
		for _, c := range []struct{ token, item string }{
			{"GITHUB_TOKEN", r.job},
			{"FORSGREN_TOKEN", r.forsgren},
			{"", r.unnamed()},
		} {
			t.Run(c.token, func(t *testing.T) {
				fake := newSetupServer(t, 201)
				_, stdout, _ := checkNeedsWithDenied(t, r, c.token, "")
				wantCreatedWith(t, fake, c.item, stdout)
			})
		}
	})
}

// TestCheckNeedsReadsTheDeniedFileItIsGiven: --pulls-denied and
// --pushes-denied name the file instead of the one in data/.
func TestCheckNeedsReadsTheDeniedFileItIsGiven(t *testing.T) {
	eachRefusedRead(t, func(t *testing.T, r refusedRead) {
		fake := newSetupServer(t, 201)
		_, stdout, _ := checkNeedsWithDenied(t, r, "GITHUB_TOKEN", "elsewhere.csv", r.flag, "elsewhere.csv")
		wantCreatedWith(t, fake, r.job, stdout)
	})
}

// TestCheckNeedsClosesTheSetupIssueOnceNoReadIsRefused: the open setup issue
// that carried the item is closed when the file no longer lists the
// repository: no file, or one a later read of acme/app emptied.
func TestCheckNeedsClosesTheSetupIssueOnceNoReadIsRefused(t *testing.T) {
	t.Setenv("GITHUB_REPOSITORY", "acme/data")
	eachRefusedRead(t, func(t *testing.T, r refusedRead) {
		for _, token := range []string{noFile, emptiedFile} {
			t.Run(token, func(t *testing.T) {
				fake := newRecordingIssueServer(t, "open", needs.Marker+"\n\n- [ ] "+r.job)
				code, _, stderr := checkNeedsWithDenied(t, r, token, "")
				if code != 0 || stderr != "" {
					t.Errorf("want exit 0 and a quiet run, got %d, %q", code, stderr)
				}
				wantClosed(t, fake)
			})
		}
	})
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

// TestCheckNeedsFailsOnADeniedFileItCannotRead: a file in no known format
// fails the check, named on stderr, with the status failed (forsgren#395):
// the open setup issue that carried the item is neither written nor closed,
// as the refusal may still stand.
func TestCheckNeedsFailsOnADeniedFileItCannotRead(t *testing.T) {
	t.Setenv("GITHUB_REPOSITORY", "acme/data")
	eachRefusedRead(t, func(t *testing.T, r refusedRead) {
		code, got, writes := checkNeedsWithCorruptDenied(t, r)
		if code != 0 {
			t.Errorf("want exit 0, got %d", code)
		}
		wantAllIn(t, got, "check-needs: failed", "the refused "+r.noun+" reads are unknown", "bad.csv")
		if len(writes) != 0 {
			t.Errorf("want the setup issue left as it is, got %q", writes)
		}
	})
}

// checkNeedsWithCorruptDenied runs check-needs with r's flag naming a file in
// no known format, against an open setup issue that carries r's item. It
// returns the exit code, stdout and stderr together, and the issue writes.
func checkNeedsWithCorruptDenied(t *testing.T, r refusedRead) (int, string, []string) {
	t.Helper()
	fake := newRecordingIssueServer(t, "open", needs.Marker+"\n\n- [ ] "+r.job)
	setVersion(t, "0.4.0")
	t.Setenv("GITHUB_TOKEN", testToken)
	installationWithIssuesWrite(t)
	if err := os.WriteFile("bad.csv", []byte("not a denied file\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	code, stdout, stderr := runCommand("check-needs", "--config", "forsgren.config.yml",
		"--repository", "acme/data", r.flag, "bad.csv")
	return code, stdout + stderr, fake.writes
}

// wantAllIn fails t unless got has every one of wants.
func wantAllIn(t *testing.T, got string, wants ...string) {
	t.Helper()
	for _, want := range wants {
		if !strings.Contains(got, want) {
			t.Errorf("want %q in %q", want, got)
		}
	}
}
