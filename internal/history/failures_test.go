package history

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"
)

const (
	failuresHead = "# forsgren failures v1\n" +
		"repository,issue,opened_at,closed_at,failure_start\n"
	// openLine is the file line of issue(42), open.
	openLine = "acme/app,42,2026-09-01T10:00:00Z,,2026-09-01T09:30:00Z\n"
	// closedLine is the file line of closed(issue(42), 5).
	closedLine = "acme/app,42,2026-09-01T10:00:00Z,2026-09-01T15:00:00Z,2026-09-01T09:30:00Z\n"
)

// issue is an open failure issue of the made-up acme/app, opened number-42
// hours after day, failure-start half an hour before it opened.
func issue(number int64) Failure {
	opened := day.Add(time.Duration(number-42) * time.Hour)
	return Failure{Repository: "acme/app", Issue: number, OpenedAt: opened, FailureStart: opened.Add(-30 * time.Minute)}
}

// closed is f closed hours after it was opened.
func closed(f Failure, hours int) Failure {
	f.ClosedAt = f.OpenedAt.Add(time.Duration(hours) * time.Hour)
	return f
}

// failuresPath is a path in a data/ directory that does not exist yet.
func failuresPath(t *testing.T) string {
	t.Helper()
	return filepath.Join(t.TempDir(), "data", "failures.csv")
}

// storeFailures appends failures to path and fails the test on an error.
func storeFailures(t *testing.T, path string, failures ...Failure) int {
	t.Helper()
	n, err := AppendFailures(path, failures)
	if err != nil {
		t.Fatalf("want AppendFailures to succeed, got %v", err)
	}
	return n
}

// wantFailures fails the test unless LoadFailures of path is want.
func wantFailures(t *testing.T, path string, want ...Failure) {
	t.Helper()
	got, err := LoadFailures(path)
	if err != nil {
		t.Fatalf("want LoadFailures to succeed, got %v", err)
	}
	if !slices.Equal(got, want) {
		t.Errorf("want the failures\n%v\ngot\n%v", want, got)
	}
}

// TestAppendFailuresCreatesTheFileWithItsVersion (forsgren#18, step 1):
// data/ and the file are created by the first call; an open issue has an
// empty closed_at.
func TestAppendFailuresCreatesTheFileWithItsVersion(t *testing.T) {
	path := failuresPath(t)
	if n := storeFailures(t, path, issue(42)); n != 1 {
		t.Errorf("want 1 line stored, got %d", n)
	}
	if got := readFile(t, path); got != failuresHead+openLine {
		t.Errorf("want the version line, the columns and the issue, got\n%q", got)
	}
	wantFailures(t, path, issue(42))
}

// TestAnEmptyFailureStartIsStoredEmpty: an issue whose body holds no
// failure-start keeps that column empty, and reads back as the zero time.
func TestAnEmptyFailureStartIsStoredEmpty(t *testing.T) {
	path := failuresPath(t)
	unknown := issue(42)
	unknown.FailureStart = time.Time{}
	storeFailures(t, path, unknown)
	if got := readFile(t, path); got != failuresHead+"acme/app,42,2026-09-01T10:00:00Z,,\n" {
		t.Errorf("want two empty columns, got\n%q", got)
	}
	wantFailures(t, path, unknown)
}

// TestAnUnchangedIssueIsNotWrittenAgain: an issue whose newest line says
// the same is not appended, and the file is not even opened for writing.
func TestAnUnchangedIssueIsNotWrittenAgain(t *testing.T) {
	content := failuresHead + openLine
	path := writeFile(t, content)
	sameButCase := issue(42)
	sameButCase.Repository = "Acme/App"
	if n := storeFailures(t, path, issue(42), sameButCase); n != 0 {
		t.Errorf("want 0 lines stored, got %d", n)
	}
	assertUntouched(t, path, content)
}

// TestAClosedIssueGetsANewLineAndTheNewestLineWins: the file only grows, so
// an issue stored open and later closed gets a second line; LoadFailures
// gives the issue once, as its newest line says.
func TestAClosedIssueGetsANewLineAndTheNewestLineWins(t *testing.T) {
	path := failuresPath(t)
	storeFailures(t, path, issue(42))
	if n := storeFailures(t, path, closed(issue(42), 5)); n != 1 {
		t.Errorf("want 1 new line for the closed issue, got %d", n)
	}
	if got := readFile(t, path); got != failuresHead+openLine+closedLine {
		t.Errorf("want the open line kept and the closed one after it, got\n%q", got)
	}
	wantFailures(t, path, closed(issue(42), 5))
}

// TestAReopenedIssueIsOpenAgain: a line is compared with the issue's newest
// line, not with any line: open, closed, open again is three lines, and the
// issue is open.
func TestAReopenedIssueIsOpenAgain(t *testing.T) {
	path := failuresPath(t)
	storeFailures(t, path, issue(42))
	storeFailures(t, path, closed(issue(42), 5))
	if n := storeFailures(t, path, issue(42)); n != 1 {
		t.Errorf("want the reopened issue stored, got %d lines", n)
	}
	if got := readFile(t, path); got != failuresHead+openLine+closedLine+openLine {
		t.Errorf("want three lines, got\n%q", got)
	}
	wantFailures(t, path, issue(42))
}

// TestTheIssueKeyIsTheRepositoryAndTheNumber: the same number in another
// repository is another issue; within one call the last state of an issue
// wins, each change once.
func TestTheIssueKeyIsTheRepositoryAndTheNumber(t *testing.T) {
	path := failuresPath(t)
	other := issue(42)
	other.Repository = "acme/api"
	if n := storeFailures(t, path, issue(42), other, issue(42), closed(issue(42), 2)); n != 3 {
		t.Errorf("want 3 lines (acme/app open, acme/api, acme/app closed), got %d", n)
	}
	wantFailures(t, path, other, closed(issue(42), 2))
}

// TestNewFailureLinesAreInOpeningOrder: by opened_at, then repository, then
// issue number; LoadFailures keeps the order in which issues first appear.
func TestNewFailureLinesAreInOpeningOrder(t *testing.T) {
	path := failuresPath(t)
	api := issue(43)
	api.Repository = "acme/api"
	storeFailures(t, path, issue(44), issue(43), api, issue(42))
	storeFailures(t, path, closed(issue(42), 1))
	wantFailures(t, path, closed(issue(42), 1), api, issue(43), issue(44))
}

// TestLoadFailuresGivesUTC: times stored from another zone come back in UTC.
func TestLoadFailuresGivesUTC(t *testing.T) {
	path := failuresPath(t)
	local := closed(issue(42), 3)
	cest := time.FixedZone("CEST", 2*3600)
	local.OpenedAt, local.ClosedAt, local.FailureStart = local.OpenedAt.In(cest), local.ClosedAt.In(cest),
		local.FailureStart.In(cest)
	storeFailures(t, path, local)
	wantFailures(t, path, closed(issue(42), 3))
}

// TestTheFailuresFileRefusesAnUnknownVersionUntouched: both calls refuse a
// v2, and a commits file is not a failures file.
func TestTheFailuresFileRefusesAnUnknownVersionUntouched(t *testing.T) {
	content := "# forsgren failures v2\nrepository,whatever\n"
	path := writeFile(t, content)
	if _, err := AppendFailures(path, []Failure{issue(42)}); !errors.Is(err, ErrUnknownVersion) {
		t.Errorf("want ErrUnknownVersion from AppendFailures, got %v", err)
	}
	if _, err := LoadFailures(path); !errors.Is(err, ErrUnknownVersion) {
		t.Errorf("want ErrUnknownVersion from LoadFailures, got %v", err)
	}
	assertUntouched(t, path, content)
	if _, err := LoadFailures(writeFile(t, commitsHead+commitLine)); !errors.Is(err, ErrMalformed) {
		t.Errorf("want ErrMalformed for a commits file, got %v", err)
	}
}

// TestAMalformedFailuresFileIsRefusedWithItsLineNumber: both calls name the
// line; AppendFailures writes nothing.
func TestAMalformedFailuresFileIsRefusedWithItsLineNumber(t *testing.T) {
	good := strings.TrimSuffix(closedLine, "\n")
	edit := func(old, replacement string) string {
		return failuresHead + strings.Replace(good, old, replacement, 1) + "\n"
	}
	for name, c := range map[string]struct {
		content string
		line    int
	}{
		"no column line":      {"# forsgren failures v1\n" + openLine, 2},
		"four fields":         {failuresHead + openLine + "acme/app,43,2026-09-01T10:00:00Z,\n", 4},
		"issue not a number":  {edit(",42,", ",4x2,"), 3},
		"issue zero":          {edit(",42,", ",0,"), 3},
		"no opened_at":        {edit(",2026-09-01T10:00:00Z,", ",,"), 3},
		"bad closed_at":       {edit("2026-09-01T15:00:00Z", "yesterday"), 3},
		"bad failure_start":   {edit(",2026-09-01T09:30:00Z", ",2026-09-01T09:30+02:00"), 3},
		"repository not o/n":  {edit("acme/app", "app"), 3},
		"blank line in there": {failuresHead + openLine + "\n" + openLine, 4},
	} {
		t.Run(name, func(t *testing.T) {
			path := writeFile(t, c.content)
			_, loadErr := LoadFailures(path)
			_, appendErr := AppendFailures(path, []Failure{issue(50)})
			for call, err := range map[string]error{"LoadFailures": loadErr, "AppendFailures": appendErr} {
				var m *MalformedError
				if !errors.As(err, &m) || m.Line != c.line {
					t.Errorf("%s: want ErrMalformed at line %d, got %v", call, c.line, err)
				}
			}
			assertUntouched(t, path, c.content)
		})
	}
}

// TestAppendFailuresRefusesAnIssueItCannotStoreAndCreatesNothing.
func TestAppendFailuresRefusesAnIssueItCannotStoreAndCreatesNothing(t *testing.T) {
	for name, mutate := range map[string]func(*Failure){
		"not owner/name":        func(f *Failure) { f.Repository = "app" },
		"line break":            func(f *Failure) { f.Repository = "acme/a\npp" },
		"no issue number":       func(f *Failure) { f.Issue = 0 },
		"no opening time":       func(f *Failure) { f.OpenedAt = time.Time{} },
		"fraction of opening":   func(f *Failure) { f.OpenedAt = day.Add(time.Millisecond) },
		"fraction of closing":   func(f *Failure) { f.ClosedAt = day.Add(time.Millisecond) },
		"fraction of the start": func(f *Failure) { f.FailureStart = day.Add(time.Millisecond) },
	} {
		t.Run(name, func(t *testing.T) {
			path := failuresPath(t)
			f := issue(42)
			mutate(&f)
			if _, err := AppendFailures(path, []Failure{issue(43), f}); !errors.Is(err, ErrInvalidRecord) {
				t.Errorf("want ErrInvalidRecord, got %v", err)
			}
			if _, err := os.Stat(filepath.Dir(path)); !errors.Is(err, fs.ErrNotExist) {
				t.Errorf("want no data/ directory created, got %v", err)
			}
		})
	}
}

// TestLoadFailuresOfAMissingFileIsNotExist: reported, not created.
func TestLoadFailuresOfAMissingFileIsNotExist(t *testing.T) {
	path := failuresPath(t)
	if _, err := LoadFailures(path); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("want fs.ErrNotExist, got %v", err)
	}
	if _, err := os.Stat(filepath.Dir(path)); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("want nothing created, got %v", err)
	}
}
