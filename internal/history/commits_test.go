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
	sha3        = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	commitsHead = "# forsgren commits v2\n" +
		"repository,kind,deployment_id,commit,authored_at,deployed_at,author\n"
	// commitLine is the file line of cmt(1001, sha1, 0), whose author is unknown.
	commitLine = "acme/app,environment,1001," + sha1 + ",2026-09-01T10:00:00Z,2026-09-01T11:00:00Z,\n"
	// commitsHeadV1 and commitLineV1 are the same file as the commits format v1
	// wrote it, before forsgren stored the author (forsgren#273).
	commitsHeadV1 = "# forsgren commits v1\n" +
		"repository,kind,deployment_id,commit,authored_at,deployed_at\n"
	commitLineV1 = "acme/app,environment,1001," + sha1 + ",2026-09-01T10:00:00Z,2026-09-01T11:00:00Z\n"
)

// cmt is a valid commit of deployment id of the made-up acme/app: authored
// minutes after day, deployed id-1000 hours after day.
func cmt(id int64, sha string, minutes int) Commit {
	return Commit{
		Repository: "acme/app", Kind: KindEnvironment, DeploymentID: id, SHA: sha,
		AuthoredAt: day.Add(time.Duration(minutes) * time.Minute),
		DeployedAt: day.Add(time.Duration(id-1000) * time.Hour),
	}
}

// commitsPath is a path in a data/ directory that does not exist yet.
func commitsPath(t *testing.T) string {
	t.Helper()
	return filepath.Join(t.TempDir(), "data", "commits.csv")
}

func mustAppendCommits(t *testing.T, path string, commits ...Commit) int {
	t.Helper()
	n, err := AppendCommits(path, commits)
	if err != nil {
		t.Fatalf("want AppendCommits to succeed, got %v", err)
	}
	return n
}

func mustLoadCommits(t *testing.T, path string) []Commit {
	t.Helper()
	got, err := LoadCommits(path)
	if err != nil {
		t.Fatalf("want LoadCommits to succeed, got %v", err)
	}
	return got
}

// TestAppendCommitsCreatesTheFileWithItsVersion: data/ and the file are
// created by the first call, the version line first, then the columns.
func TestAppendCommitsCreatesTheFileWithItsVersion(t *testing.T) {
	path := commitsPath(t)
	if n := mustAppendCommits(t, path, cmt(1001, sha1, 0)); n != 1 {
		t.Errorf("want 1 commit stored, got %d", n)
	}
	if got := readFile(t, path); got != commitsHead+commitLine {
		t.Errorf("want the version line, the columns and the commit, got\n%q", got)
	}
}

// TestAppendCommitsWithNothingToStoreStillCreatesTheFile, as the
// deployments' history does: the file says its version from the first run.
func TestAppendCommitsWithNothingToStoreStillCreatesTheFile(t *testing.T) {
	path := commitsPath(t)
	if n := mustAppendCommits(t, path); n != 0 {
		t.Errorf("want 0 commits stored, got %d", n)
	}
	if got := readFile(t, path); got != commitsHead {
		t.Errorf("want only the version and column lines, got %q", got)
	}
	if got := mustLoadCommits(t, path); len(got) != 0 {
		t.Errorf("want no commits, got %v", got)
	}
}

// TestAppendCommitsAddsToAnExistingFile: what is there stays byte for byte.
func TestAppendCommitsAddsToAnExistingFile(t *testing.T) {
	path := commitsPath(t)
	mustAppendCommits(t, path, cmt(1001, sha1, 0))
	before := readFile(t, path)
	if n := mustAppendCommits(t, path, cmt(1002, sha2, 5)); n != 1 {
		t.Errorf("want 1 commit stored, got %d", n)
	}
	if after := readFile(t, path); !strings.HasPrefix(after, before) || strings.Count(after, "\n") != 4 {
		t.Errorf("want the old content then one new line, got\n%q", after)
	}
	if got := mustLoadCommits(t, path); !slices.Equal(got, []Commit{cmt(1001, sha1, 0), cmt(1002, sha2, 5)}) {
		t.Errorf("want both commits in file order, got %v", got)
	}
}

// TestAppendCommitsSkipsWhatIsAlreadyThere: the key is the repository
// (ignoring case), the kind, the deployment ID and the SHA; the first line
// stays, and a repeat inside one call counts once.
func TestAppendCommitsSkipsWhatIsAlreadyThere(t *testing.T) {
	path := commitsPath(t)
	mustAppendCommits(t, path, cmt(1001, sha1, 0))
	changed := cmt(1001, sha1, 7)
	changed.Repository, changed.DeployedAt = "Acme/App", changed.DeployedAt.Add(time.Minute)
	otherKind := cmt(1001, sha1, 0)
	otherKind.Kind = KindWorkflow
	otherRepository := cmt(1001, sha1, 0)
	otherRepository.Repository = "acme/api"
	repeat := cmt(1001, sha2, 1)
	fresh := []Commit{changed, repeat, repeat, cmt(1002, sha1, 0), otherKind, otherRepository}
	if n := mustAppendCommits(t, path, fresh...); n != 4 {
		t.Errorf("want 4 new commits stored, got %d", n)
	}
	got := mustLoadCommits(t, path)
	if len(got) != 5 || got[0] != cmt(1001, sha1, 0) {
		t.Errorf("want the first line kept and 4 new ones, got %v", got)
	}
}

// TestAppendCommitsOfOnlyDuplicatesLeavesTheFileAlone: nothing new, the file
// is not opened for writing, not even its modification time changes.
func TestAppendCommitsOfOnlyDuplicatesLeavesTheFileAlone(t *testing.T) {
	content := commitsHead + commitLine
	path := writeFile(t, content)
	if n := mustAppendCommits(t, path, cmt(1001, sha1, 0)); n != 0 {
		t.Errorf("want 0 commits stored, got %d", n)
	}
	assertUntouched(t, path, content)
}

// TestAppendCommitsWritesInDeploymentThenAuthorOrder: by deployment time,
// then each deployment's commits by author date, then SHA.
func TestAppendCommitsWritesInDeploymentThenAuthorOrder(t *testing.T) {
	path := commitsPath(t)
	mustAppendCommits(t, path, cmt(1002, sha1, 30), cmt(1001, sha2, 5), cmt(1001, sha1, 5), cmt(1001, sha3, 0))
	want := []Commit{cmt(1001, sha3, 0), cmt(1001, sha1, 5), cmt(1001, sha2, 5), cmt(1002, sha1, 30)}
	if got := mustLoadCommits(t, path); !slices.Equal(got, want) {
		t.Errorf("want %v, got %v", want, got)
	}
}

// TestLoadCommitsAfterAppendReturnsTheCommits: times that were not UTC come
// back in UTC, a release and a workflow keep their kind.
func TestLoadCommitsAfterAppendReturnsTheCommits(t *testing.T) {
	path := commitsPath(t)
	release := cmt(1003, sha2, 9)
	release.Kind = KindRelease
	workflow := cmt(1002, sha1, 3)
	workflow.Kind = KindWorkflow
	local := cmt(1001, sha1, 0)
	cest := time.FixedZone("CEST", 2*3600)
	local.AuthoredAt, local.DeployedAt = local.AuthoredAt.In(cest), local.DeployedAt.In(cest)
	mustAppendCommits(t, path, release, local, workflow)
	want := []Commit{cmt(1001, sha1, 0), workflow, release}
	if got := mustLoadCommits(t, path); !slices.Equal(got, want) {
		t.Errorf("want %v, got %v", want, got)
	}
}

// TestTheCommitsFileRefusesAnUnknownVersionUntouched: both calls refuse it;
// a deployments history is not a commits file either.
func TestTheCommitsFileRefusesAnUnknownVersionUntouched(t *testing.T) {
	content := "# forsgren commits v3\nrepository,whatever\n"
	path := writeFile(t, content)
	if _, err := AppendCommits(path, []Commit{cmt(1001, sha1, 0)}); !errors.Is(err, ErrUnknownVersion) {
		t.Errorf("want ErrUnknownVersion from AppendCommits, got %v", err)
	}
	if _, err := LoadCommits(path); !errors.Is(err, ErrUnknownVersion) {
		t.Errorf("want ErrUnknownVersion from LoadCommits, got %v", err)
	}
	assertUntouched(t, path, content)
	deployments := writeFile(t, head+line1001)
	if _, err := LoadCommits(deployments); !errors.Is(err, ErrMalformed) {
		t.Errorf("want ErrMalformed for a deployments history, got %v", err)
	}
}

// TestAMalformedCommitsFileIsRefusedWithItsLineNumber: both calls name the
// line, and AppendCommits leaves the file untouched.
func TestAMalformedCommitsFileIsRefusedWithItsLineNumber(t *testing.T) {
	good := strings.TrimSuffix(commitLine, "\n")
	edit := func(old, replacement string) string {
		return commitsHead + strings.Replace(good, old, replacement, 1) + "\n"
	}
	for name, c := range map[string]struct {
		content string
		line    int
	}{
		"no column line":    {"# forsgren commits v2\n" + commitLine, 2},
		"too few fields":    {commitsHead + commitLine + "acme/app,environment\n", 4},
		"blank line":        {commitsHead + "\n" + commitLine, 3},
		"bad deployment ID": {edit(",1001,", ",10x1,"), 3},
		"bad commit":        {edit(sha1, "abc"), 3},
		"bad kind":          {edit("environment", "cron"), 3},
		"bad authored_at":   {edit("2026-09-01T10:00:00Z", "2026-09-01 10:00"), 3},
		"bad deployed_at":   {edit("T11:00:00Z", "T11:00:00+02:00"), 3},
		"bad repository":    {edit("acme/app", "app"), 3},
		"v1 line in a v2":   {commitsHead + commitLineV1, 3},
	} {
		t.Run(name, func(t *testing.T) {
			path := writeFile(t, c.content)
			_, loadErr := LoadCommits(path)
			_, appendErr := AppendCommits(path, []Commit{cmt(2000, sha1, 0)})
			for call, err := range map[string]error{"LoadCommits": loadErr, "AppendCommits": appendErr} {
				var m *MalformedError
				if !errors.As(err, &m) || m.Line != c.line {
					t.Errorf("%s: want ErrMalformed at line %d, got %v", call, c.line, err)
				}
			}
			assertUntouched(t, path, c.content)
		})
	}
}

// TestAppendCommitsRefusesACommitItCannotStoreAndCreatesNothing.
func TestAppendCommitsRefusesACommitItCannotStoreAndCreatesNothing(t *testing.T) {
	for name, mutate := range map[string]func(*Commit){
		"not owner/name":      func(c *Commit) { c.Repository = "app" },
		"line break":          func(c *Commit) { c.Repository = "acme/a\npp" },
		"unknown kind":        func(c *Commit) { c.Kind = "cron" },
		"no deployment ID":    func(c *Commit) { c.DeploymentID = 0 },
		"short SHA":           func(c *Commit) { c.SHA = "abc" },
		"no author date":      func(c *Commit) { c.AuthoredAt = time.Time{} },
		"fraction of author":  func(c *Commit) { c.AuthoredAt = day.Add(time.Millisecond) },
		"no deployment time":  func(c *Commit) { c.DeployedAt = time.Time{} },
		"fraction of deploy.": func(c *Commit) { c.DeployedAt = day.Add(time.Millisecond) },
	} {
		t.Run(name, func(t *testing.T) {
			path := commitsPath(t)
			c := cmt(1001, sha1, 0)
			mutate(&c)
			if _, err := AppendCommits(path, []Commit{cmt(1002, sha2, 1), c}); !errors.Is(err, ErrInvalidRecord) {
				t.Errorf("want ErrInvalidRecord, got %v", err)
			}
			if _, err := os.Stat(filepath.Dir(path)); !errors.Is(err, fs.ErrNotExist) {
				t.Errorf("want no data/ directory created, got %v", err)
			}
		})
	}
}

// TestLoadCommitsOfAMissingFileIsNotExist: reported, not created.
func TestLoadCommitsOfAMissingFileIsNotExist(t *testing.T) {
	path := commitsPath(t)
	if _, err := LoadCommits(path); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("want fs.ErrNotExist, got %v", err)
	}
	if _, err := os.Stat(filepath.Dir(path)); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("want nothing created, got %v", err)
	}
}

// v1File writes a commits file in the format v1 (no author column) with the
// lines, and returns its path.
func v1File(t *testing.T, lines ...string) string {
	t.Helper()
	return writeFile(t, commitsHeadV1+strings.Join(lines, ""))
}

// TestLoadCommitsReadsAV1FileWithNoAuthors (forsgren#273, decision 274): a
// file written before the author column is read as it is, every author empty,
// the other fields as they were.
func TestLoadCommitsReadsAV1FileWithNoAuthors(t *testing.T) {
	path := v1File(t, commitLineV1)
	got := mustLoadCommits(t, path)
	if want := []Commit{cmt(1001, sha1, 0)}; !slices.Equal(got, want) {
		t.Errorf("want %v with an empty author, got %v", want, got)
	}
	assertUntouched(t, path, commitsHeadV1+commitLineV1)
}

// TestAppendCommitsUpgradesAV1FileToV2 (forsgren#273): the first append to a v1
// file rewrites it once as v2, every old line kept with an empty author, then
// adds the new commits (with their authors) as v2 lines. It never leaves a
// file that mixes the formats, and the rewrite goes through a temporary file,
// so no temporary file is left behind. The choice, made once and pinned: the
// authors of the old commits are not known and stay empty, which is honest;
// appending v1 lines would lose the authors of every new commit.
func TestAppendCommitsUpgradesAV1FileToV2(t *testing.T) {
	path := v1File(t, commitLineV1)
	added := cmt(1002, sha2, 1)
	added.Author = "ada-dev"
	if n := mustAppendCommits(t, path, added); n != 1 {
		t.Errorf("want 1 commit stored, got %d", n)
	}
	want := commitsHead + commitLine + "acme/app,environment,1002," + sha2 +
		",2026-09-01T10:01:00Z,2026-09-01T12:00:00Z,ada-dev\n"
	assertContent(t, path, want)
	wantAlone(t, path)
	got := mustLoadCommits(t, path)
	if authors := []string{got[0].Author, got[1].Author}; !slices.Equal(authors, []string{"", "ada-dev"}) {
		t.Errorf("want the old commit with no author and the new one with its login, got %q", authors)
	}
}

// wantAlone fails unless the file at path is the only entry of its directory:
// no temporary file of the upgrade is left behind.
func wantAlone(t *testing.T, path string) {
	t.Helper()
	entries, err := os.ReadDir(filepath.Dir(path))
	if err != nil || len(entries) != 1 {
		t.Errorf("want the file alone in its directory, got %v, %v", entries, err)
	}
}

// TestAppendCommitsWithNothingNewStillUpgradesAV1File (forsgren#273): the file
// is v2 after one collect run, whether or not the run stored a commit.
func TestAppendCommitsWithNothingNewStillUpgradesAV1File(t *testing.T) {
	path := v1File(t, commitLineV1)
	if n := mustAppendCommits(t, path, cmt(1001, sha1, 0)); n != 0 {
		t.Errorf("want 0 commits stored, got %d", n)
	}
	assertContent(t, path, commitsHead+commitLine)
}

// TestAV1FileThatIsMalformedIsRefusedUntouchedOnAppend (forsgren#273): the
// upgrade rewrites only a file that read cleanly.
func TestAV1FileThatIsMalformedIsRefusedUntouchedOnAppend(t *testing.T) {
	content := commitsHeadV1 + commitLineV1 + "acme/app,environment\n"
	path := writeFile(t, content)
	if _, err := AppendCommits(path, []Commit{cmt(1002, sha2, 1)}); !errors.Is(err, ErrMalformed) {
		t.Errorf("want ErrMalformed, got %v", err)
	}
	assertUntouched(t, path, content)
}

// TestAFailedUpgradeLeavesTheV1FileUntouched (forsgren#273): when the
// rewrite cannot be written (a directory where its temporary file goes), the
// append fails naming the file, and the v1 file keeps its bytes.
func TestAFailedUpgradeLeavesTheV1FileUntouched(t *testing.T) {
	path := v1File(t, commitLineV1)
	mustMkdir(t, path+".tmp")
	_, err := AppendCommits(path, []Commit{cmt(1002, sha2, 1)})
	if err == nil || !strings.Contains(err.Error(), path) {
		t.Errorf("want an error naming %s, got %v", path, err)
	}
	assertUntouched(t, path, commitsHeadV1+commitLineV1)
}

// TestCommitsKeepTheGitHubLoginAsItIs (forsgren#273, decision 274): a login, an
// unknown author (empty) and a bot account are stored and read back exactly;
// leaving bots out is the count's job, not the file's.
func TestCommitsKeepTheGitHubLoginAsItIs(t *testing.T) {
	path := commitsPath(t)
	var commits []Commit
	for i, author := range []string{"ada-dev", "", "dependabot[bot]", "octo_cat-EMU"} {
		c := cmt(1001, "a"+strings.Repeat("0", 38)+string(rune('1'+i)), i)
		c.Author = author
		commits = append(commits, c)
	}
	mustAppendCommits(t, path, commits...)
	got := mustLoadCommits(t, path)
	for i, c := range commits {
		if got[i].Author != c.Author {
			t.Errorf("commit %d: want author %q, got %q", i, c.Author, got[i].Author)
		}
	}
}

// TestAppendCommitsRefusesAnAuthorThatIsNotALogin (forsgren#273): no email and
// no name ever reaches the file: only GitHub's login shape is stored.
func TestAppendCommitsRefusesAnAuthorThatIsNotALogin(t *testing.T) {
	for _, author := range []string{"dev@acme.example", "Acme Dev", "ada,dev", "ada\ndev", "-ada", "ada[bot", "[bot]"} {
		path := commitsPath(t)
		c := cmt(1001, sha1, 0)
		c.Author = author
		if _, err := AppendCommits(path, []Commit{c}); !errors.Is(err, ErrInvalidRecord) {
			t.Errorf("author %q: want ErrInvalidRecord, got %v", author, err)
		}
		if _, err := os.Stat(path); !errors.Is(err, fs.ErrNotExist) {
			t.Errorf("author %q: want no file written, got %v", author, err)
		}
	}
}

// TestAppendCommitsKeepsTheFirstAuthorOfAHeldCommit (forsgren#273): the key and
// the held rule are unchanged, the author is not part of the key, so a held
// commit is not written again with another author.
func TestAppendCommitsKeepsTheFirstAuthorOfAHeldCommit(t *testing.T) {
	path := commitsPath(t)
	first := cmt(1001, sha1, 0)
	first.Author = "ada-dev"
	mustAppendCommits(t, path, first)
	again := first
	again.Author = "bob-dev"
	if n := mustAppendCommits(t, path, again); n != 0 {
		t.Errorf("want the held commit skipped, got %d stored", n)
	}
	if got := mustLoadCommits(t, path); len(got) != 1 || got[0].Author != "ada-dev" {
		t.Errorf("want the first author kept, got %v", got)
	}
}

// assertContent fails unless the file at path holds exactly want.
func assertContent(t *testing.T, path, want string) {
	t.Helper()
	got, err := os.ReadFile(filepath.Clean(path))
	if err != nil || string(got) != want {
		t.Errorf("want the file to hold\n%s\ngot\n%s (%v)", want, got, err)
	}
}
