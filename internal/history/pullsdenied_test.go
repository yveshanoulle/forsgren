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

// The pulls denied format v2 (forsgren#321, step 1): the refused repository,
// when, and the name of the token that was refused; v1, without the name, is
// still read and written again as v2.

const (
	deniedV1 = "# forsgren pulls denied v1\nrepository,denied_at\nacme/app,2026-09-20T08:00:00Z\n"
	deniedV2 = "# forsgren pulls denied v2\nrepository,denied_at,token\n"
)

var deniedAt = time.Date(2026, 9, 20, 8, 0, 0, 0, time.UTC)

func deniedFile(t *testing.T, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "pulls_denied.csv")
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

// TestPullsDeniedV2RoundTripsWithTheTokenName: saved sorted by repository
// with the token's name in the third column, read back as written.
func TestPullsDeniedV2RoundTripsWithTheTokenName(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data", "pulls_denied.csv")
	want := PullsDenied{"acme/lib": {deniedAt, "GITHUB_TOKEN"}, "acme/app": {deniedAt, "FORSGREN_TOKEN"}}
	if err := SavePullsDenied(path, want); err != nil {
		t.Fatal(err)
	}
	raw, _ := os.ReadFile(filepath.Clean(path))
	const lines = "acme/app,2026-09-20T08:00:00Z,FORSGREN_TOKEN\nacme/lib,2026-09-20T08:00:00Z,GITHUB_TOKEN\n"
	if string(raw) != deniedV2+lines {
		t.Errorf("want %q, got %q", deniedV2+lines, raw)
	}
	got, err := LoadPullsDenied(path)
	if err != nil || !maps.Equal(got, want) {
		t.Errorf("want %v, got %v, %v", want, got, err)
	}
}

// TestPullsDeniedV1IsReadWithNoTokenAndWrittenAsV2: a v1 line has an empty
// token name, and the next save writes the file in v2, the empty name kept.
func TestPullsDeniedV1IsReadWithNoTokenAndWrittenAsV2(t *testing.T) {
	path := deniedFile(t, deniedV1)
	got, err := LoadPullsDenied(path)
	if err != nil || got["acme/app"] != (Denial{At: deniedAt}) {
		t.Fatalf("want acme/app at %v with no token, got %v, %v", deniedAt, got, err)
	}
	if err := SavePullsDenied(path, got); err != nil {
		t.Fatal(err)
	}
	raw, _ := os.ReadFile(filepath.Clean(path))
	if want := deniedV2 + "acme/app,2026-09-20T08:00:00Z,\n"; string(raw) != want {
		t.Errorf("want %q, got %q", want, raw)
	}
}

// TestPullsDeniedHoldsATokenNameNeverAValue: a token column that is no
// environment variable name (a value looks like ghp_..., lower case) is
// refused on read and on save, so a value never reaches the file.
func TestPullsDeniedHoldsATokenNameNeverAValue(t *testing.T) {
	const value = "ghp_0123456789abcdef"
	_, err := LoadPullsDenied(deniedFile(t, deniedV2+"acme/app,2026-09-20T08:00:00Z,"+value+"\n"))
	var malformed *MalformedError
	if !errors.As(err, &malformed) || malformed.Line != 3 {
		t.Errorf("want a malformed line 3, got %v", err)
	} else if strings.Contains(err.Error(), value) {
		t.Errorf("want an error that does not quote the value, got %v", err)
	}
	path := filepath.Join(t.TempDir(), "pulls_denied.csv")
	if err := SavePullsDenied(path, PullsDenied{"acme/app": {deniedAt, value}}); err == nil {
		t.Error("want a refusal to save a value, got none")
	}
}

// TestPullsDeniedSplitsIntoTimesAndTokens: the mark files keep a time per
// repository; Times, Tokens and DeniedOf are the way between the two.
func TestPullsDeniedSplitsIntoTimesAndTokens(t *testing.T) {
	d := PullsDenied{"acme/app": {deniedAt, "FORSGREN_TOKEN"}}
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

// TestPullsDeniedMissingIsEmptyAndAnUnwritablePathIsAnError: a missing file
// notes no refusal, like the other mark files; a directory that cannot be
// made fails the save naming the path.
func TestPullsDeniedMissingIsEmptyAndAnUnwritablePathIsAnError(t *testing.T) {
	dir := t.TempDir()
	if got, err := LoadPullsDenied(filepath.Join(dir, "missing.csv")); err != nil || len(got) != 0 {
		t.Errorf("want no denial and no error, got %v, %v", got, err)
	}
	blocker := deniedFile(t, "")
	path := filepath.Join(blocker, "data", "pulls_denied.csv")
	if err := SavePullsDenied(path, PullsDenied{}); err == nil || !strings.Contains(err.Error(), path) {
		t.Errorf("want an error naming %s, got %v", path, err)
	}
}
