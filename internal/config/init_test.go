package config

import (
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"
)

// starterLines is Starter split into lines.
func starterLines() []string {
	return strings.Split(strings.TrimSuffix(Starter, "\n"), "\n")
}

// starterConfig is the config at the end of the starter: one that measures
// nothing yet, its root page the standard view with the switch (forsgren#51).
const starterConfig = "version: 1\nview: standard\nprojects: []\n"

// isStarterLine says whether a line may stand in the starter: blank, a
// comment, or one of the lines of starterConfig.
func isStarterLine(line string) bool {
	return line == "" || strings.HasPrefix(line, "#") || slices.Contains(strings.Split(starterConfig, "\n"), line)
}

// TestStarterIsACommentedGuideThenAnEmptyConfig: the starter is a header and
// an example, all comments, and then exactly the lines of a config that
// measures nothing yet (forsgren#12), view: standard among them
// (forsgren#51).
func TestStarterIsACommentedGuideThenAnEmptyConfig(t *testing.T) {
	if !strings.HasSuffix(Starter, "\n"+starterConfig) {
		t.Fatalf("want the starter to end in %q, got:\n%s", starterConfig, Starter)
	}
	for _, line := range starterLines() {
		if !isStarterLine(line) {
			t.Errorf("want only comments and the lines of %q, got %q", starterConfig, line)
		}
	}
}

// TestStarterExplainsItself: the header says what the file is, names the
// command that checks it, and lists the three deployment forms.
func TestStarterExplainsItself(t *testing.T) {
	for _, want := range []string{
		"forsgren.config.yml", "forsgren check-config --config forsgren.config.yml",
		"environment=<name>", "workflow=<file>.yml", "release", "production",
	} {
		if !strings.Contains(Starter, want) {
			t.Errorf("want the starter to mention %q", want)
		}
	}
}

// uncommentedExample is the example of the starter as a config: the comment
// block that starts at its `# version: 1` line, without the comment marks.
func uncommentedExample(t *testing.T) string {
	t.Helper()
	lines := starterLines()
	start := -1
	for i, line := range lines {
		if line == "# version: 1" {
			start = i
			break
		}
	}
	if start < 0 {
		t.Fatalf("want an example in the starter that starts at a line `# version: 1`, got:\n%s", Starter)
	}
	var example []string
	for _, line := range lines[start:] {
		if !strings.HasPrefix(line, "#") {
			break
		}
		example = append(example, strings.TrimPrefix(strings.TrimPrefix(line, "#"), " "))
	}
	return strings.Join(example, "\n") + "\n"
}

// deploymentKinds is the set of deployment kinds the repositories of cfg use.
func deploymentKinds(cfg Config) map[DeploymentKind]bool {
	kinds := map[DeploymentKind]bool{}
	for _, p := range cfg.Projects {
		for _, r := range p.Repositories {
			kinds[r.Deployment.Kind] = true
		}
	}
	return kinds
}

// TestStarterExampleIsAValidConfig: the commented example, once uncommented,
// is a config check-config accepts, and it shows the default deployment,
// workflow= and release.
func TestStarterExampleIsAValidConfig(t *testing.T) {
	example := uncommentedExample(t)
	cfg, err := parse([]byte(example))
	if err != nil {
		t.Fatalf("want the uncommented example valid, got %v", err)
	}
	kinds := deploymentKinds(cfg)
	for _, kind := range []DeploymentKind{Environment, Workflow, Release} {
		if !kinds[kind] {
			t.Errorf("want the example to show deployment kind %d", kind)
		}
	}
	if !strings.Contains(example, "name: acme/api\n") {
		t.Errorf("want a repository with no deployment line, the default")
	}
}

// TestStarterExampleLabelsRows (forsgren#38): the example names a
// repository's row and its services' rows, both label forms.
func TestStarterExampleLabelsRows(t *testing.T) {
	example := uncommentedExample(t)
	cfg, err := parse([]byte(example))
	if err != nil {
		t.Fatalf("want the uncommented example valid, got %v", err)
	}
	if cfg.LabelCount() < 2 {
		t.Errorf("want at least two labels in the example, got %d:\n%s", cfg.LabelCount(), example)
	}
	for _, form := range []string{"label: ", "services:\n"} {
		if !strings.Contains(example, form) {
			t.Errorf("want the example to show %q, got:\n%s", form, example)
		}
	}
}

// wantPrefix fails the test for each of names that lacks prefix.
func wantPrefix(t *testing.T, names []string, prefix string) {
	t.Helper()
	for _, name := range names {
		if !strings.HasPrefix(name, prefix) {
			t.Errorf("want made-up names that start with %q only, got %q", prefix, name)
		}
	}
}

// TestStarterExampleUsesMadeUpNames: acme names only, never a real one.
func TestStarterExampleUsesMadeUpNames(t *testing.T) {
	cfg, err := parse([]byte(uncommentedExample(t)))
	if err != nil {
		t.Fatalf("want the uncommented example valid, got %v", err)
	}
	var projects, repositories []string
	for _, p := range cfg.Projects {
		projects = append(projects, p.Name)
		for _, r := range p.Repositories {
			repositories = append(repositories, r.Name)
		}
	}
	wantPrefix(t, projects, "Acme")
	wantPrefix(t, repositories, "acme/")
	if len(repositories) == 0 {
		t.Error("want repositories in the example")
	}
}

// writeFile writes content to path, or fails the test.
func writeFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
}

// readFile returns the content of path, or fails the test.
func readFile(t *testing.T, path string) string {
	t.Helper()
	got, err := os.ReadFile(filepath.Clean(path))
	if err != nil {
		t.Fatal(err)
	}
	return string(got)
}

// wantEntries fails the test unless dir holds exactly n entries (no temp
// file left behind, nothing created that should not be).
func wantEntries(t *testing.T, dir string, n int) {
	t.Helper()
	list, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(list) != n {
		t.Errorf("want %d entries in %s, got %d: %v", n, dir, len(list), list)
	}
}

// TestStarterPassesLoad: the starter is a config Load accepts, with no
// projects.
func TestStarterPassesLoad(t *testing.T) {
	path := filepath.Join(t.TempDir(), "forsgren.config.yml")
	writeFile(t, path, Starter)
	cfg, err := Load(path)
	if err != nil {
		t.Fatalf("want the starter to load, got %v", err)
	}
	if cfg.Version != 1 || len(cfg.Projects) != 0 {
		t.Errorf("want version 1 and no projects, got %+v", cfg)
	}
}

func TestInitWritesTheStarterWhenTheFileIsMissing(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "forsgren.config.yml")
	created, err := Init(path)
	if err != nil || !created {
		t.Fatalf("want created and no error, got %v, %v", created, err)
	}
	if got := readFile(t, path); got != Starter {
		t.Errorf("want the starter written, got %q", got)
	}
	// A new installation starts with the view switch (forsgren#51).
	if cfg, err := Load(path); err != nil || cfg.View != ViewStandard {
		t.Errorf("want the written file to pass Load with view standard, got %q, %v", cfg.View, err)
	}
	wantEntries(t, dir, 1)
}

// TestInitLeavesAnExistingFileAlone: whatever the file holds, valid, invalid,
// empty or only comments, Init keeps it byte for byte and does not touch its
// modification time (forsgren#12: an existing file is never rewritten).
func TestInitLeavesAnExistingFileAlone(t *testing.T) {
	cases := map[string]string{
		"valid":        "version: 1\nprojects:\n  - name: Acme\n    repositories:\n      - name: acme/app\n",
		"invalid":      "version: 2\nprojcts: [\n",
		"empty":        "",
		"comments":     "# mine\n",
		"no newline":   "version: 1\nprojects: []",
		"not yaml":     "\x00\x01 binary \xff",
		"windows ends": "version: 1\r\nprojects: []\r\n",
	}
	for name, content := range cases {
		t.Run(name, func(t *testing.T) { checkKept(t, content) })
	}
}

// checkKept: Init keeps a file with this content, its bytes and its
// modification time, and leaves nothing else in the directory.
func checkKept(t *testing.T, content string) {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, "forsgren.config.yml")
	old := keepOld(t, path, content)
	created, err := Init(path)
	if err != nil || created {
		t.Fatalf("want kept and no error, got created %v, %v", created, err)
	}
	if got := readFile(t, path); got != content {
		t.Errorf("want the file untouched, got %q", got)
	}
	if got := modTime(t, path); !got.Equal(old) {
		t.Errorf("want mtime %v kept, got %v", old, got)
	}
	wantEntries(t, dir, 1)
}

// keepOld writes content to path, sets its modification time long ago and
// returns that time.
func keepOld(t *testing.T, path, content string) time.Time {
	t.Helper()
	old := time.Date(2001, 2, 3, 4, 5, 6, 0, time.UTC)
	writeFile(t, path, content)
	if err := os.Chtimes(path, old, old); err != nil {
		t.Fatal(err)
	}
	return old
}

// modTime is the modification time of path.
func modTime(t *testing.T, path string) time.Time {
	t.Helper()
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	return info.ModTime()
}

// TestInitNeverClobbersAFileThatAppearsFirst: the file is created between
// Init's look and its write, here by the hook that runs just before the file
// is put in place. The write must keep what appeared, not replace it.
func TestInitNeverClobbersAFileThatAppearsFirst(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "forsgren.config.yml")
	created, err := install(path, func() { writeFile(t, path, "mine\n") })
	if err != nil || created {
		t.Fatalf("want kept and no error, got created %v, %v", created, err)
	}
	if got := readFile(t, path); got != "mine\n" {
		t.Errorf("want the file that appeared kept, got %q", got)
	}
	wantEntries(t, dir, 1)
}

// TestInitReportsAFailedLink: the link fails for another reason than a taken
// path, here because the temporary file is gone: an error, no file written.
func TestInitReportsAFailedLink(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "forsgren.config.yml")
	vanish := func() {
		list, err := os.ReadDir(dir)
		if err != nil {
			t.Error(err)
		}
		for _, e := range list {
			if err := os.Remove(filepath.Join(dir, e.Name())); err != nil {
				t.Error(err)
			}
		}
	}
	created, err := install(path, vanish)
	if created || !errors.Is(err, ErrWrite) {
		t.Fatalf("want ErrWrite, got created %v, %v", created, err)
	}
	wantEntries(t, dir, 0)
}

// initOutcome is what one Init call returned.
type initOutcome struct {
	created bool
	err     error
}

// tally counts the Inits that created the file and lists those that failed.
func tally(outcomes []initOutcome) (made int, failures []error) {
	for _, o := range outcomes {
		if o.created {
			made++
		}
		if o.err != nil {
			failures = append(failures, o.err)
		}
	}
	return made, failures
}

// TestInitRacersCreateTheFileOnce: many Inits on one missing path, at once:
// exactly one creates it, none fails, and the file is the whole starter.
func TestInitRacersCreateTheFileOnce(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "forsgren.config.yml")
	outcomes := make([]initOutcome, 24)
	var wg sync.WaitGroup
	for i := range outcomes {
		wg.Go(func() { outcomes[i].created, outcomes[i].err = Init(path) })
	}
	wg.Wait()
	made, failures := tally(outcomes)
	if made != 1 || len(failures) != 0 {
		t.Errorf("want exactly one Init to create the file and none to fail, got %d, %v", made, failures)
	}
	if got := readFile(t, path); got != Starter {
		t.Errorf("want the whole starter, got %q", got)
	}
	wantEntries(t, dir, 1)
}

func TestInitRefusesADirectory(t *testing.T) {
	dir := t.TempDir()
	created, err := Init(dir)
	if created || !errors.Is(err, ErrNotAFile) {
		t.Fatalf("want ErrNotAFile, got created %v, %v", created, err)
	}
	if !strings.HasPrefix(err.Error(), dir+": ") {
		t.Errorf("want the message to start with the path, got %q", err)
	}
	wantEntries(t, dir, 0)
}

// TestInitDoesNotCreateAMissingParentDirectory: a mistyped directory is
// an error, not a new directory with a config nobody looks at.
func TestInitDoesNotCreateAMissingParentDirectory(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "typo", "forsgren.config.yml")
	created, err := Init(path)
	if created || !errors.Is(err, ErrWrite) {
		t.Fatalf("want ErrWrite, got created %v, %v", created, err)
	}
	if !strings.HasPrefix(err.Error(), path+": ") {
		t.Errorf("want the message to start with the path, got %q", err)
	}
	wantEntries(t, dir, 0)
}

// TestInitRefusesALinkToNothing: a link whose target is missing is taken, so
// Init neither keeps it as a config nor writes through it.
func TestInitRefusesALinkToNothing(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "forsgren.config.yml")
	if err := os.Symlink(filepath.Join(dir, "nowhere.yml"), path); err != nil {
		t.Fatal(err)
	}
	created, err := Init(path)
	if created || !errors.Is(err, ErrNotAFile) {
		t.Fatalf("want ErrNotAFile, got created %v, %v", created, err)
	}
	wantEntries(t, dir, 1)
}

// TestInitRefusesAParentThatIsAFile: the parent exists but is a file.
func TestInitRefusesAParentThatIsAFile(t *testing.T) {
	parent := filepath.Join(t.TempDir(), "file")
	writeFile(t, parent, "x")
	created, err := Init(filepath.Join(parent, "forsgren.config.yml"))
	if created || !errors.Is(err, ErrWrite) {
		t.Fatalf("want ErrWrite, got created %v, %v", created, err)
	}
}
