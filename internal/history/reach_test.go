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

const reachHead = "# forsgren reach v1\nrepository,reach\n"

// reachPath is a path in a data/ directory that does not exist yet.
func reachPath(t *testing.T) string {
	t.Helper()
	return filepath.Join(t.TempDir(), "data", "reach.csv")
}

// someReach is the reach of two made-up repositories.
func someReach() Reach {
	return Reach{
		"acme/web": time.Date(2026, 7, 3, 0, 0, 0, 0, time.UTC),
		"acme/app": time.Date(2026, 6, 1, 12, 30, 0, 0, time.UTC),
	}
}

// TestReachRoundTrips (forsgren#57): what SaveReach writes, LoadReach reads
// back, for two repositories, in a directory that is made on the way.
func TestReachRoundTrips(t *testing.T) {
	path := reachPath(t)
	if err := SaveReach(path, someReach()); err != nil {
		t.Fatalf("want SaveReach to succeed, got %v", err)
	}
	got, err := LoadReach(path)
	if err != nil || !maps.Equal(got, someReach()) {
		t.Errorf("want %v and no error, got %v, %v", someReach(), got, err)
	}
}

// TestAMissingReachFileIsAnEmptyReach: a repository never read has no file
// yet, which is no error, and the empty Reach is one a caller can write to.
func TestAMissingReachFileIsAnEmptyReach(t *testing.T) {
	got, err := LoadReach(reachPath(t))
	if err != nil || got == nil || len(got) != 0 {
		t.Errorf("want an empty, non-nil Reach and no error, got %v, %v", got, err)
	}
}

// TestSaveReachWritesTheVersionColumnsAndRowsSortedByRepository pins the file
// byte for byte: the version line, the columns, then a row per repository
// sorted by name, its date in UTC to the second.
func TestSaveReachWritesTheVersionColumnsAndRowsSortedByRepository(t *testing.T) {
	path := reachPath(t)
	if err := SaveReach(path, someReach()); err != nil {
		t.Fatalf("want SaveReach to succeed, got %v", err)
	}
	want := reachHead + "acme/app,2026-06-01T12:30:00Z\nacme/web,2026-07-03T00:00:00Z\n"
	if got := readFile(t, path); got != want {
		t.Errorf("want\n%q\ngot\n%q", want, got)
	}
}

// TestSaveReachReplacesWhatIsThere: the marker moves, so a second save
// leaves only the second reach in the file.
func TestSaveReachReplacesWhatIsThere(t *testing.T) {
	path := reachPath(t)
	if err := SaveReach(path, someReach()); err != nil {
		t.Fatal(err)
	}
	later := Reach{"acme/app": time.Date(2026, 3, 4, 0, 0, 0, 0, time.UTC)}
	if err := SaveReach(path, later); err != nil {
		t.Fatalf("want the second SaveReach to succeed, got %v", err)
	}
	if got := readFile(t, path); got != reachHead+"acme/app,2026-03-04T00:00:00Z\n" {
		t.Errorf("want only the second reach, got %q", got)
	}
}

// writeReach writes content to a reach.csv in a data/ directory made for it.
func writeReach(t *testing.T, content string) string {
	t.Helper()
	path := reachPath(t)
	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

// TestLoadReachRefusesAMalformedRow: a date that is not RFC 3339 UTC is a
// *MalformedError naming reach.csv and its line.
func TestLoadReachRefusesAMalformedRow(t *testing.T) {
	path := writeReach(t, reachHead+"acme/app,2026-06-01T12:30:00Z\nacme/web,last tuesday\n")
	_, err := LoadReach(path)
	var malformed *MalformedError
	if !errors.As(err, &malformed) || malformed.Line != 4 {
		t.Fatalf("want a *MalformedError at line 4, got %v", err)
	}
	if !strings.Contains(err.Error(), "reach.csv") || !errors.Is(err, ErrMalformed) {
		t.Errorf("want ErrMalformed naming reach.csv, got %v", err)
	}
}
