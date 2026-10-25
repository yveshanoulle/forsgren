package history

import (
	"errors"
	"maps"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// The denied format v2 (forsgren#321, step 1, and forsgren#414 for the pushes):
// the refused repository, when, and the name of the token that was refused; v1,
// without the name, is still read and written again as v2. pulls_denied.csv
// and pushes_denied.csv are the one format under two names.

var deniedAt = time.Date(2026, 9, 20, 8, 0, 0, 0, time.UTC)

// deniedKind is one of the two denied files: what it refuses the read of
// (pulls, pushes) and how it is read and written.
type deniedKind struct {
	name string
	load func(string) (Denied, error)
	save func(string, Denied) error
}

var deniedKinds = []deniedKind{
	{"pulls", LoadPullsDenied, SavePullsDenied},
	{"pushes", LoadPushesDenied, SavePushesDenied},
}

// eachDenied runs check as a subtest of every denied file.
func eachDenied(t *testing.T, check func(*testing.T, deniedKind)) {
	t.Helper()
	for _, k := range deniedKinds {
		t.Run(k.name, func(t *testing.T) { check(t, k) })
	}
}

// file is the name of k's file.
func (k deniedKind) file() string { return k.name + "_denied.csv" }

// v1 is k's file of the format v1, with one line.
func (k deniedKind) v1() string {
	return "# forsgren " + k.name + " denied v1\nrepository,denied_at\nacme/app,2026-09-20T08:00:00Z\n"
}

// v2 is the head of k's file of the format v2.
func (k deniedKind) v2() string {
	return "# forsgren " + k.name + " denied v2\nrepository,denied_at,token\n"
}

// written is a file of k with content, and its path.
func (k deniedKind) written(t *testing.T, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), k.file())
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

// TestDeniedV2RoundTripsWithTheTokenName: saved sorted by repository with the
// token's name in the third column, read back as written.
func TestDeniedV2RoundTripsWithTheTokenName(t *testing.T) {
	eachDenied(t, func(t *testing.T, k deniedKind) {
		path := filepath.Join(t.TempDir(), "data", k.file())
		want := Denied{"acme/lib": {deniedAt, "GITHUB_TOKEN"}, "acme/app": {deniedAt, "FORSGREN_TOKEN"}}
		if err := k.save(path, want); err != nil {
			t.Fatal(err)
		}
		raw, _ := os.ReadFile(filepath.Clean(path))
		const lines = "acme/app,2026-09-20T08:00:00Z,FORSGREN_TOKEN\nacme/lib,2026-09-20T08:00:00Z,GITHUB_TOKEN\n"
		if string(raw) != k.v2()+lines {
			t.Errorf("want %q, got %q", k.v2()+lines, raw)
		}
		got, err := k.load(path)
		if err != nil || !maps.Equal(got, want) {
			t.Errorf("want %v, got %v, %v", want, got, err)
		}
	})
}

// TestDeniedV1IsReadWithNoTokenAndWrittenAsV2: a v1 line has an empty token
// name, and the next save writes the file in v2, the empty name kept.
func TestDeniedV1IsReadWithNoTokenAndWrittenAsV2(t *testing.T) {
	eachDenied(t, func(t *testing.T, k deniedKind) {
		path := k.written(t, k.v1())
		got, err := k.load(path)
		if err != nil || got["acme/app"] != (Denial{At: deniedAt}) {
			t.Fatalf("want acme/app at %v with no token, got %v, %v", deniedAt, got, err)
		}
		if err := k.save(path, got); err != nil {
			t.Fatal(err)
		}
		raw, _ := os.ReadFile(filepath.Clean(path))
		if want := k.v2() + "acme/app,2026-09-20T08:00:00Z,\n"; string(raw) != want {
			t.Errorf("want %q, got %q", want, raw)
		}
	})
}

// TestDeniedHoldsATokenNameNeverAValue: a token column that is no environment
// variable name (a value looks like ghp_..., lower case) is refused on read
// and on save, so a value never reaches the file.
func TestDeniedHoldsATokenNameNeverAValue(t *testing.T) {
	eachDenied(t, func(t *testing.T, k deniedKind) {
		const value = "ghp_0123456789abcdef"
		_, err := k.load(k.written(t, k.v2()+"acme/app,2026-09-20T08:00:00Z,"+value+"\n"))
		var malformed *MalformedError
		if !errors.As(err, &malformed) || malformed.Line != 3 {
			t.Errorf("want a malformed line 3, got %v", err)
		} else if strings.Contains(err.Error(), value) {
			t.Errorf("want an error that does not quote the value, got %v", err)
		}
		path := filepath.Join(t.TempDir(), k.file())
		if err := k.save(path, Denied{"acme/app": {deniedAt, value}}); err == nil {
			t.Error("want a refusal to save a value, got none")
		}
	})
}

// TestDeniedSplitsIntoTimesAndTokens: the mark files keep a time per
// repository; Times, Tokens and DeniedOf are the way between the two.
func TestDeniedSplitsIntoTimesAndTokens(t *testing.T) {
	d := Denied{"acme/app": {deniedAt, "FORSGREN_TOKEN"}}
	times, tokens := d.Times(), d.Tokens()
	if !times["acme/app"].Equal(deniedAt) || tokens["acme/app"] != "FORSGREN_TOKEN" {
		t.Fatalf("want the time and the token, got %v and %v", times, tokens)
	}
	if got := DeniedOf(times, tokens); got["acme/app"] != d["acme/app"] {
		t.Errorf("want %v back, got %v", d, got)
	}
	if got := DeniedOf(times, nil); got["acme/app"] != (Denial{At: deniedAt}) {
		t.Errorf("want no token for a repository without one, got %v", got)
	}
}

// TestDeniedMissingIsEmptyAndAnUnwritablePathIsAnError: a missing file notes
// no refusal, like the other mark files; a directory that cannot be made
// fails the save naming the path.
func TestDeniedMissingIsEmptyAndAnUnwritablePathIsAnError(t *testing.T) {
	eachDenied(t, func(t *testing.T, k deniedKind) {
		dir := t.TempDir()
		if got, err := k.load(filepath.Join(dir, "missing.csv")); err != nil || len(got) != 0 {
			t.Errorf("want no denial and no error, got %v, %v", got, err)
		}
		blocker := k.written(t, "")
		path := filepath.Join(blocker, "data", k.file())
		if err := k.save(path, Denied{}); err == nil || !strings.Contains(err.Error(), path) {
			t.Errorf("want an error naming %s, got %v", path, err)
		}
	})
}
