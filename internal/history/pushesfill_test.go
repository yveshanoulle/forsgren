package history

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// TestPushesFillRoundTrips (forsgren#583, step 2): data/pushes_fill.csv holds,
// per repository, when its push fill last moved and GitHub's after cursor of
// the next page to read, written and read back as is.
func TestPushesFillRoundTrips(t *testing.T) {
	path := filepath.Join(t.TempDir(), "pushes_fill.csv")
	at := time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC)
	fill := PushesFill{"acme/app": {At: at, Cursor: "Y3Vyc29yOnYyOpK7MjAy"}}
	if err := SavePushesFill(path, fill); err != nil {
		t.Fatal(err)
	}
	raw, _ := os.ReadFile(filepath.Clean(path))
	want := "# forsgren pushes fill v1\nrepository,filled_at,cursor\nacme/app,2026-10-01T00:00:00Z,Y3Vyc29yOnYyOpK7MjAy\n"
	if string(raw) != want {
		t.Errorf("want %q, got %q", want, raw)
	}
	got, err := LoadPushesFill(path)
	if err != nil || got["acme/app"] != fill["acme/app"] {
		t.Errorf("want %+v back, got %+v, %v", fill, got, err)
	}
}

// TestPushesFillRefusesACursorThatIsNoCursor: a cursor holds the letters,
// digits and the four signs of base64 only, so a line that holds anything
// else (a comma, a space, a token's prefix sign) is refused.
func TestPushesFillRefusesACursorThatIsNoCursor(t *testing.T) {
	path := filepath.Join(t.TempDir(), "pushes_fill.csv")
	at := time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC)
	if err := SavePushesFill(path, PushesFill{"acme/app": {At: at, Cursor: "a b"}}); err == nil {
		t.Error("want a cursor with a space refused")
	}
	raw := "# forsgren pushes fill v1\nrepository,filled_at,cursor\nacme/app,2026-10-01T00:00:00Z,\n"
	if err := os.WriteFile(path, []byte(raw), 0o600); err != nil {
		t.Fatal(err)
	}
	var malformed *MalformedError
	if _, err := LoadPushesFill(path); !errors.As(err, &malformed) {
		t.Errorf("want an empty cursor malformed, got %v", err)
	}
}

// TestLoadPushesFillOfNoFileIsEmpty: a missing file holds no cursor.
func TestLoadPushesFillOfNoFileIsEmpty(t *testing.T) {
	got, err := LoadPushesFill(filepath.Join(t.TempDir(), "none.csv"))
	if err != nil || len(got) != 0 {
		t.Errorf("want none, got %+v, %v", got, err)
	}
}

// TestPushesFillSplitsIntoTimesAndCursorsAndBack: the mark files keep the
// times, the cursors are kept beside them, and the two make the fill again.
func TestPushesFillSplitsIntoTimesAndCursorsAndBack(t *testing.T) {
	at := time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC)
	fill := PushesFill{"acme/app": {At: at, Cursor: "c2"}}
	back := PushesFillOf(fill.Times(), fill.Cursors())
	if len(back) != 1 || back["acme/app"] != fill["acme/app"] {
		t.Errorf("want %+v back, got %+v", fill, back)
	}
}
