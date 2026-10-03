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
	sha1 = "0123456789abcdef0123456789abcdef01234567"
	sha2 = "fedcba9876543210fedcba9876543210fedcba98"
	head = "# forsgren history v1\n" +
		"project,repository,kind,name,deployment_id,commit,created_at,state,task\n"
)

var day = time.Date(2026, 9, 1, 10, 0, 0, 0, time.UTC)

// rec is a valid record of the made-up acme/app: the ID and the minutes after
// day vary, everything else is the same.
func rec(id int64, minutes int) Record {
	return Record{
		Project: "shop", Repository: "acme/app", Kind: KindEnvironment, Name: "production", ID: id,
		Commit: sha1, CreatedAt: day.Add(time.Duration(minutes) * time.Minute), State: StateSuccess,
	}
}

// line is the file line of rec(1001, 0).
const line1001 = "shop,acme/app,environment,production,1001," + sha1 + ",2026-09-01T10:00:00Z,success,\n"

// historyPath is a path in a data/ directory that does not exist yet.
func historyPath(t *testing.T) string {
	t.Helper()
	return filepath.Join(t.TempDir(), "data", "deployments.csv")
}

func readFile(t *testing.T, path string) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Clean(path))
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

// writeFile writes content with a modification time long ago, so a later
// write shows in it.
func writeFile(t *testing.T, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "deployments.csv")
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	old := time.Date(2020, 1, 2, 3, 4, 5, 0, time.UTC)
	if err := os.Chtimes(path, old, old); err != nil {
		t.Fatal(err)
	}
	return path
}

func mustAppend(t *testing.T, path string, records ...Record) int {
	t.Helper()
	n, err := Append(path, records)
	if err != nil {
		t.Fatalf("want Append to succeed, got %v", err)
	}
	return n
}

func mustLoad(t *testing.T, path string) []Record {
	t.Helper()
	got, err := Load(path)
	if err != nil {
		t.Fatalf("want Load to succeed, got %v", err)
	}
	return got
}

// assertUntouched fails unless the file still has content and the old
// modification time that writeFile gave it.
func assertUntouched(t *testing.T, path, content string) {
	t.Helper()
	if got := readFile(t, path); got != content {
		t.Errorf("want the file untouched, got\n%q\nwant\n%q", got, content)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.ModTime().Year() != 2020 {
		t.Errorf("want the modification time untouched, got %v", info.ModTime())
	}
}

// TestAppendCreatesTheMissingDirectory: data/ is created by the first
// Append (forsgren#9).
func TestAppendCreatesTheMissingDirectory(t *testing.T) {
	path := historyPath(t)
	if n := mustAppend(t, path, rec(1001, 0)); n != 1 {
		t.Errorf("want 1 record stored, got %d", n)
	}
	if got := readFile(t, path); got != head+line1001 {
		t.Errorf("want the version line, the columns and the record, got\n%q", got)
	}
}

// TestAppendCreatesTheMissingFileWithItsVersion: a missing file in an
// existing directory starts with the version line, then the column line.
func TestAppendCreatesTheMissingFileWithItsVersion(t *testing.T) {
	path := filepath.Join(t.TempDir(), "deployments.csv")
	mustAppend(t, path, rec(1001, 0), rec(1002, 5))
	want := head + line1001 +
		"shop,acme/app,environment,production,1002," + sha1 + ",2026-09-01T10:05:00Z,success,\n"
	if got := readFile(t, path); got != want {
		t.Errorf("want\n%q\ngot\n%q", want, got)
	}
}

// TestAppendWithNothingToStoreStillCreatesTheFile: a first run that finds no
// deployment leaves a history that says its version.
func TestAppendWithNothingToStoreStillCreatesTheFile(t *testing.T) {
	path := historyPath(t)
	if n := mustAppend(t, path); n != 0 {
		t.Errorf("want 0 records stored, got %d", n)
	}
	if got := readFile(t, path); got != head {
		t.Errorf("want only the version and column lines, got %q", got)
	}
	if got := mustLoad(t, path); len(got) != 0 {
		t.Errorf("want no records, got %v", got)
	}
}

// TestAppendAddsToAnExistingFile: what is there stays byte for byte, the new
// lines come after it.
func TestAppendAddsToAnExistingFile(t *testing.T) {
	path := historyPath(t)
	mustAppend(t, path, rec(1001, 0))
	before := readFile(t, path)
	if n := mustAppend(t, path, rec(1002, 5)); n != 1 {
		t.Errorf("want 1 record stored, got %d", n)
	}
	after := readFile(t, path)
	if !strings.HasPrefix(after, before) || strings.Count(after, "\n") != 4 {
		t.Errorf("want the old content then one new line, got\n%q", after)
	}
	if got := mustLoad(t, path); !slices.Equal(got, []Record{rec(1001, 0), rec(1002, 5)}) {
		t.Errorf("want both records in file order, got %v", got)
	}
}

// TestAppendSkipsWhatIsAlreadyThere: the key is repository, kind and ID; the
// first line stays whatever a later record says, and a repeat inside one call
// counts once.
func TestAppendSkipsWhatIsAlreadyThere(t *testing.T) {
	path := historyPath(t)
	mustAppend(t, path, rec(1001, 0))
	changed := rec(1001, 0)
	changed.State = StateFailure
	repeat := rec(1003, 9)
	if n := mustAppend(t, path, []Record{changed, repeat, repeat, rec(1002, 5)}...); n != 2 {
		t.Errorf("want 2 new records stored, got %d", n)
	}
	got := mustLoad(t, path)
	want := []Record{rec(1001, 0), rec(1002, 5), rec(1003, 9)}
	if !slices.Equal(got, want) {
		t.Errorf("want %v, got %v", want, got)
	}
}

// TestTheSameIDInAnotherRepositoryOrKindIsAnotherDeployment: IDs are only
// unique within a repository and a kind.
func TestTheSameIDInAnotherRepositoryOrKindIsAnotherDeployment(t *testing.T) {
	path := historyPath(t)
	otherRepository := rec(1001, 1)
	otherRepository.Repository = "acme/api"
	otherKind := rec(1001, 2)
	otherKind.Kind, otherKind.Name = KindWorkflow, "deploy.yml"
	if n := mustAppend(t, path, rec(1001, 0), otherRepository, otherKind); n != 3 {
		t.Errorf("want 3 records stored, got %d", n)
	}
}

// TestTheRepositoryOfTheKeyIgnoresCase: GitHub's repository names ignore
// case, and so does the config, so Acme/App and acme/app are one repository
// and the line written first stays (forsgren#12, step 8).
func TestTheRepositoryOfTheKeyIgnoresCase(t *testing.T) {
	path := historyPath(t)
	first := rec(1001, 0)
	first.Repository = "Acme/App"
	mustAppend(t, path, first)
	if n := mustAppend(t, path, rec(1001, 0), rec(1002, 5)); n != 1 {
		t.Errorf("want 1 new record stored, got %d", n)
	}
	got := mustLoad(t, path)
	want := []Record{first, rec(1002, 5)}
	if !slices.Equal(got, want) {
		t.Errorf("want %v, got %v", want, got)
	}
}

// TestAppendOfOnlyDuplicatesLeavesTheFileAlone: nothing new, nothing
// written, not even the modification time.
func TestAppendOfOnlyDuplicatesLeavesTheFileAlone(t *testing.T) {
	content := head + line1001
	path := writeFile(t, content)
	if n := mustAppend(t, path, rec(1001, 0)); n != 0 {
		t.Errorf("want 0 records stored, got %d", n)
	}
	assertUntouched(t, path, content)
}

// TestAppendWritesTheNewLinesInCreatedAtOrderThenID.
func TestAppendWritesTheNewLinesInCreatedAtOrderThenID(t *testing.T) {
	path := historyPath(t)
	mustAppend(t, path, rec(1004, 7), rec(1003, 5), rec(1002, 5), rec(1001, 9))
	var ids []int64
	for _, r := range mustLoad(t, path) {
		ids = append(ids, r.ID)
	}
	if want := []int64{1002, 1003, 1004, 1001}; !slices.Equal(ids, want) {
		t.Errorf("want IDs %v, got %v", want, ids)
	}
}

// TestAnUnknownVersionIsRefusedAndTouchedNot: both calls refuse, and the
// file's bytes and modification time are as they were.
func TestAnUnknownVersionIsRefusedAndTouchedNot(t *testing.T) {
	content := "# forsgren history v2\nproject,repository,whatever\n"
	path := writeFile(t, content)
	if _, err := Append(path, []Record{rec(1001, 0)}); !errors.Is(err, ErrUnknownVersion) {
		t.Errorf("want ErrUnknownVersion from Append, got %v", err)
	}
	if _, err := Load(path); !errors.Is(err, ErrUnknownVersion) {
		t.Errorf("want ErrUnknownVersion from Load, got %v", err)
	}
	assertUntouched(t, path, content)
}

// TestAMalformedFileIsRefusedWithItsLineNumber: Load and Append name the
// line, and Append leaves the file untouched.
func TestAMalformedFileIsRefusedWithItsLineNumber(t *testing.T) {
	good := strings.TrimSuffix(line1001, "\n")
	for name, c := range map[string]struct {
		content string
		line    int
	}{
		"empty file":         {"", 1},
		"not a history":      {"hello\n", 1},
		"no column line":     {"# forsgren history v1\n" + line1001, 2},
		"only the version":   {"# forsgren history v1\n", 2},
		"too few fields":     {head + line1001 + "shop,acme/app\n", 4},
		"blank line":         {head + line1001 + "\n" + line1001, 4},
		"unterminated quote": {head + line1001 + "\"shop,acme/app\n", 4},
		"bad deployment ID":  {head + strings.Replace(good, "1001", "10x1", 1) + "\n", 3},
		"zero deployment ID": {head + strings.Replace(good, "1001", "0", 1) + "\n", 3},
		"bad time":           {head + strings.Replace(good, "2026-09-01T10:00:00Z", "2026-09-01 10:00", 1) + "\n", 3},
		"time not in UTC":    {head + strings.Replace(good, "T10:00:00Z", "T10:00:00+02:00", 1) + "\n", 3},
		"bad kind":           {head + strings.Replace(good, "environment", "cron", 1) + "\n", 3},
		"bad state":          {head + line1001 + strings.Replace(good, "success", "in_progress", 1) + "\n", 4},
		"bad commit":         {head + strings.Replace(good, sha1, "abc", 1) + "\n", 3},
		"CRLF line ends":     {strings.ReplaceAll(head+line1001, "\n", "\r\n"), 1},
	} {
		t.Run(name, func(t *testing.T) {
			path := writeFile(t, c.content)
			for call, err := range map[string]error{"Load": loadErr(path), "Append": appendErr(path)} {
				var m *MalformedError
				if !errors.Is(err, ErrMalformed) || !errors.As(err, &m) || m.Line != c.line {
					t.Errorf("%s: want ErrMalformed at line %d, got %v", call, c.line, err)
				}
			}
			assertUntouched(t, path, c.content)
		})
	}
}

func loadErr(path string) error {
	_, err := Load(path)
	return err
}

func appendErr(path string) error {
	_, err := Append(path, []Record{rec(2000, 0)})
	return err
}

// TestTheMalformedErrorSaysTheLine: the message names the file, the line and
// the reason.
func TestTheMalformedErrorSaysTheLine(t *testing.T) {
	path := writeFile(t, head+line1001+"shop,acme/app\n")
	err := loadErr(path)
	if err == nil {
		t.Fatal("want Load to refuse the file, got no error")
	}
	msg := err.Error()
	for _, want := range []string{path, "line 4", "malformed history", "9 comma-separated fields"} {
		if !strings.Contains(msg, want) {
			t.Errorf("want %q in %q", want, msg)
		}
	}
}

// TestAppendHandlesAFileWithoutATrailingNewline: the last line is kept and a
// newline separates it from the first new line.
func TestAppendHandlesAFileWithoutATrailingNewline(t *testing.T) {
	content := strings.TrimSuffix(head+line1001, "\n")
	path := writeFile(t, content)
	if got := mustLoad(t, path); !slices.Equal(got, []Record{rec(1001, 0)}) {
		t.Errorf("want Load to read the last line, got %v", got)
	}
	mustAppend(t, path, rec(1002, 5))
	want := content + "\nshop,acme/app,environment,production,1002," + sha1 + ",2026-09-01T10:05:00Z,success,\n"
	if got := readFile(t, path); got != want {
		t.Errorf("want\n%q\ngot\n%q", want, got)
	}
}

// TestLoadAfterAppendReturnsTheRecords: the round trip, with fields that need
// quoting, an empty and a long task, and times that were not UTC.
func TestLoadAfterAppendReturnsTheRecords(t *testing.T) {
	path := historyPath(t)
	tricky := rec(1002, 5)
	tricky.Project, tricky.Name, tricky.Task = `shop, "web"`, "deploy.yml", `a,b "c" é #1`
	tricky.Kind, tricky.State, tricky.Commit = KindWorkflow, StateOther, sha2
	release := rec(1003, 6)
	release.Kind, release.Name, release.State = KindRelease, "", StateFailure
	local := rec(1004, 7)
	local.CreatedAt = local.CreatedAt.In(time.FixedZone("CEST", 2*3600))
	mustAppend(t, path, local, release, tricky, rec(1001, 0))
	// Load gives the moment of the local record in UTC.
	want := []Record{rec(1001, 0), tricky, release, rec(1004, 7)}
	if got := mustLoad(t, path); !slices.Equal(got, want) {
		t.Errorf("want %v, got %v", want, got)
	}
}

// TestAppendRefusesARecordItCannotStoreAndCreatesNothing.
func TestAppendRefusesARecordItCannotStoreAndCreatesNothing(t *testing.T) {
	bad := map[string]func(*Record){
		"no project":        func(r *Record) { r.Project = "" },
		"not owner/name":    func(r *Record) { r.Repository = "app" },
		"too many slashes":  func(r *Record) { r.Repository = "acme/app/x" },
		"unknown kind":      func(r *Record) { r.Kind = "cron" },
		"no environment":    func(r *Record) { r.Name = "" },
		"no ID":             func(r *Record) { r.ID = 0 },
		"short commit":      func(r *Record) { r.Commit = "abc" },
		"upper-case commit": func(r *Record) { r.Commit = strings.ToUpper(sha1) },
		"no time":           func(r *Record) { r.CreatedAt = time.Time{} },
		"fraction":          func(r *Record) { r.CreatedAt = day.Add(time.Millisecond) },
		"running":           func(r *Record) { r.State = "in_progress" },
		"line break":        func(r *Record) { r.Task = "a\nb" },
	}
	for name, mutate := range bad {
		t.Run(name, func(t *testing.T) {
			path := historyPath(t)
			r := rec(1001, 0)
			mutate(&r)
			if _, err := Append(path, []Record{rec(1002, 1), r}); !errors.Is(err, ErrInvalidRecord) {
				t.Errorf("want ErrInvalidRecord, got %v", err)
			}
			if _, err := os.Stat(filepath.Dir(path)); !errors.Is(err, fs.ErrNotExist) {
				t.Errorf("want no data/ directory created, got %v", err)
			}
		})
	}
}

// TestLoadOfAMissingFileIsNotExist: Load reports it, it does not create it.
func TestLoadOfAMissingFileIsNotExist(t *testing.T) {
	path := historyPath(t)
	if err := loadErr(path); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("want fs.ErrNotExist, got %v", err)
	}
	if _, err := os.Stat(filepath.Dir(path)); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("want nothing created, got %v", err)
	}
}

// TestAppendReportsWhatItCannotReadOrCreate: a directory where the file
// should be, and a file where data/ should be.
func TestAppendReportsWhatItCannotReadOrCreate(t *testing.T) {
	dir := t.TempDir()
	if err := appendErr(dir); err == nil || errors.Is(err, ErrMalformed) {
		t.Errorf("want a read error for a directory, got %v", err)
	}
	blocker := filepath.Join(dir, "data")
	if err := os.WriteFile(blocker, []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := appendErr(filepath.Join(blocker, "deployments.csv")); err == nil {
		t.Error("want an error when data is a file")
	}
	if got := readFile(t, blocker); got != "x" {
		t.Errorf("want the file untouched, got %q", got)
	}
}

// TestAppendReportsADirectoryItCannotCreate: data/ is a link to nothing, so
// it is neither there nor can it be made; nothing is written.
func TestAppendReportsADirectoryItCannotCreate(t *testing.T) {
	dir := t.TempDir()
	if err := os.Symlink(filepath.Join(dir, "nowhere"), filepath.Join(dir, "data")); err != nil {
		t.Fatal(err)
	}
	if err := appendErr(filepath.Join(dir, "data", "deployments.csv")); err == nil {
		t.Error("want an error when data/ cannot be created")
	}
	if _, err := os.Lstat(filepath.Join(dir, "nowhere")); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("want nothing created behind the link, got %v", err)
	}
}

// TestAppendDoesNotTruncateAFileThatAppearedAfterTheLook: a new file is
// opened with O_EXCL.
func TestAppendDoesNotTruncateAFileThatAppearedAfterTheLook(t *testing.T) {
	path := filepath.Join(t.TempDir(), "deployments.csv")
	if err := os.WriteFile(path, []byte("mine"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := write(path, store{}, []Record{rec(1001, 0)}); err == nil {
		t.Error("want an error for a file that is there")
	}
	if got := readFile(t, path); got != "mine" {
		t.Errorf("want the file untouched, got %q", got)
	}
}
