package history

import (
	"errors"
	"io/fs"
	"os"
	"reflect"
	"strings"
	"testing"
	"time"
)

const (
	// commitsHeadV2 and commitLineV2 are cmt(1001, sha1, 0) by ada-dev as the
	// commits format v2 wrote it, before forsgren stored the parents and the
	// committer date (forsgren#254).
	commitsHeadV2 = "# forsgren commits v2\n" +
		"repository,kind,deployment_id,commit,authored_at,deployed_at,author\n"
	commitLineV2 = "acme/app,environment,1001," + sha1 + ",2026-09-01T10:00:00Z,2026-09-01T11:00:00Z,ada-dev\n"
	// commitLineV2InV3 is commitLineV2 as the upgrade writes it: the author
	// kept, the parents and the committer date unknown.
	commitLineV2InV3 = "acme/app,environment,1001," + sha1 + ",2026-09-01T10:00:00Z,2026-09-01T11:00:00Z,ada-dev,,\n"
	// mergeLine is the file line of merge().
	mergeLine = "acme/app,environment,1002," + sha2 + ",2026-09-01T10:01:00Z,2026-09-01T12:00:00Z,ada-dev," +
		sha3 + " " + sha1 + ",2026-09-01T11:30:00Z\n"
)

// merge is a merge commit of deployment 1002: its first parent sha3, the line
// it was made on, sorts after its second, sha1, the line it brought in; its
// committer date, half an hour before the deployment, is given in CEST.
func merge() Commit {
	c := cmt(1002, sha2, 1)
	c.Author = "ada-dev"
	c.Parents = []string{sha3, sha1}
	c.CommittedAt = time.Date(2026, 9, 1, 13, 30, 0, 0, time.FixedZone("CEST", 2*3600))
	return c
}

// inUTC is c as a load gives it back: its committer date in UTC.
func inUTC(c Commit) Commit {
	if !c.CommittedAt.IsZero() {
		c.CommittedAt = c.CommittedAt.UTC()
	}
	return c
}

// v2File writes a commits file in the format v2 (no parents and no committer
// date) with the lines, and returns its path.
func v2File(t *testing.T, lines ...string) string {
	t.Helper()
	return writeFile(t, commitsHeadV2+strings.Join(lines, ""))
}

// TestCommitsKeepTheParentsInOrderAndTheCommitterDate (forsgren#254): the
// parents come back in the order they were given, the first parent first, not
// sorted; the committer date in UTC, never the author date; a commit with no
// parents and no committer date comes back with none.
func TestCommitsKeepTheParentsInOrderAndTheCommitterDate(t *testing.T) {
	path := commitsPath(t)
	single := cmt(1003, sha3, 2)
	single.Parents = []string{sha2}
	single.CommittedAt = day.Add(3 * time.Hour)
	unknown := cmt(1001, sha1, 0)
	mustAppendCommits(t, path, merge(), single, unknown)
	if got := readFile(t, path); !strings.Contains(got, mergeLine) {
		t.Errorf("want the merge's line\n%q\nin\n%q", mergeLine, got)
	}
	want := []Commit{unknown, inUTC(merge()), single}
	if got := mustLoadCommits(t, path); !reflect.DeepEqual(got, want) {
		t.Errorf("want\n%v\ngot\n%v", want, got)
	}
}

// TestLoadCommitsReadsAV2FileWithNoParents (forsgren#254): a file written
// before the parents and committer date columns is read as it is, the author
// kept, no parents and no committer date.
func TestLoadCommitsReadsAV2FileWithNoParents(t *testing.T) {
	path := v2File(t, commitLineV2)
	want := cmt(1001, sha1, 0)
	want.Author = "ada-dev"
	if got := mustLoadCommits(t, path); !reflect.DeepEqual(got, []Commit{want}) {
		t.Errorf("want %v with no parents and no committer date, got %v", want, got)
	}
	assertUntouched(t, path, commitsHeadV2+commitLineV2)
}

// TestAppendCommitsUpgradesAV2FileToV3 (forsgren#254): the first append to a
// v2 file rewrites it once as v3, every old line kept with its author and with
// no parents and no committer date, which are not known for them, then adds
// the new commits with theirs; no temporary file is left behind.
func TestAppendCommitsUpgradesAV2FileToV3(t *testing.T) {
	path := v2File(t, commitLineV2)
	if n := mustAppendCommits(t, path, merge()); n != 1 {
		t.Errorf("want 1 commit stored, got %d", n)
	}
	assertContent(t, path, commitsHead+commitLineV2InV3+mergeLine)
	wantAlone(t, path)
}

// TestAppendCommitsWithNothingNewStillUpgradesAV2File (forsgren#254): the file
// is v3 after one collect run, whether or not the run stored a commit.
func TestAppendCommitsWithNothingNewStillUpgradesAV2File(t *testing.T) {
	path := v2File(t, commitLineV2)
	if n := mustAppendCommits(t, path, cmt(1001, sha1, 0)); n != 0 {
		t.Errorf("want 0 commits stored, got %d", n)
	}
	assertContent(t, path, commitsHead+commitLineV2InV3)
}

// TestAV2FileThatIsMalformedIsRefusedUntouchedOnAppend (forsgren#254): the
// upgrade rewrites only a v2 file that read cleanly.
func TestAV2FileThatIsMalformedIsRefusedUntouchedOnAppend(t *testing.T) {
	content := commitsHeadV2 + commitLineV2 + "acme/app,environment\n"
	path := writeFile(t, content)
	if _, err := AppendCommits(path, []Commit{merge()}); !errors.Is(err, ErrMalformed) {
		t.Errorf("want ErrMalformed, got %v", err)
	}
	assertUntouched(t, path, content)
}

// TestAMalformedParentsOrCommitterDateIsRefusedWithItsLineNumber
// (forsgren#254): both calls name the line, and AppendCommits leaves the file
// untouched.
func TestAMalformedParentsOrCommitterDateIsRefusedWithItsLineNumber(t *testing.T) {
	good := strings.TrimSuffix(mergeLine, "\n")
	for name, line := range map[string]string{
		"short parent":           strings.Replace(good, sha3+" ", "abc ", 1),
		"upper-case parent":      strings.Replace(good, sha3, strings.ToUpper(sha3), 1),
		"two spaces":             strings.Replace(good, " "+sha1, "  "+sha1, 1),
		"trailing space":         strings.Replace(good, sha1+",", sha1+" ,", 1),
		"bad committed_at":       strings.Replace(good, "2026-09-01T11:30:00Z", "2026-09-01 11:30", 1),
		"committed_at an offset": strings.Replace(good, "T11:30:00Z", "T13:30:00+02:00", 1),
		"v2 line in a v3":        strings.TrimSuffix(commitLineV2, "\n"),
	} {
		t.Run(name, func(t *testing.T) {
			content := commitsHead + commitLine + line + "\n"
			path := writeFile(t, content)
			_, loadErr := LoadCommits(path)
			_, appendErr := AppendCommits(path, []Commit{cmt(2000, sha1, 0)})
			for call, err := range map[string]error{"LoadCommits": loadErr, "AppendCommits": appendErr} {
				var m *MalformedError
				if !errors.As(err, &m) || m.Line != 4 {
					t.Errorf("%s: want ErrMalformed at line 4, got %v", call, err)
				}
			}
			assertUntouched(t, path, content)
		})
	}
}

// TestAppendCommitsRefusesParentsOrACommitterDateItCannotStore (forsgren#254):
// a parent must be a SHA, so no parent can hold the space that parts them, and
// the committer date is whole seconds; nothing is written.
func TestAppendCommitsRefusesParentsOrACommitterDateItCannotStore(t *testing.T) {
	for name, mutate := range map[string]func(*Commit){
		"short parent":           func(c *Commit) { c.Parents = []string{"abc"} },
		"empty parent":           func(c *Commit) { c.Parents = []string{sha1, ""} },
		"two in one":             func(c *Commit) { c.Parents = []string{sha1 + " " + sha2} },
		"fraction of committer.": func(c *Commit) { c.CommittedAt = day.Add(time.Millisecond) },
	} {
		t.Run(name, func(t *testing.T) {
			path := commitsPath(t)
			c := merge()
			mutate(&c)
			if _, err := AppendCommits(path, []Commit{c}); !errors.Is(err, ErrInvalidRecord) {
				t.Errorf("want ErrInvalidRecord, got %v", err)
			}
			if _, err := os.Stat(path); !errors.Is(err, fs.ErrNotExist) {
				t.Errorf("want no file written, got %v", err)
			}
		})
	}
}

// TestAppendCommitsKeepsTheFirstParentsOfAHeldCommit (forsgren#254): the key
// and the held rule are unchanged, neither the parents nor the committer date
// is part of the key, so a held commit is not written again with others.
func TestAppendCommitsKeepsTheFirstParentsOfAHeldCommit(t *testing.T) {
	path := commitsPath(t)
	mustAppendCommits(t, path, merge())
	again := merge()
	again.Parents, again.CommittedAt = []string{sha1}, day
	if n := mustAppendCommits(t, path, again); n != 0 {
		t.Errorf("want the held commit skipped, got %d stored", n)
	}
	if got := mustLoadCommits(t, path); !reflect.DeepEqual(got, []Commit{inUTC(merge())}) {
		t.Errorf("want the first parents and committer date kept, got %v", got)
	}
}
