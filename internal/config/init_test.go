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

// pageValuesComment is what the comment of each page key of the starter says
// of the three values (forsgren#200).
const pageValuesComment = "true: generated and in the menu; unlisted: generated, no menu entry; false: not generated"

// starterConfig is the config at the end of the starter: one that measures
// nothing yet, its root page the standard view marked in the menu (forsgren#51, #128),
// and auto-merge of forsgren's Dependabot updates on at major level
// (forsgren#58, #150).
const starterConfig = "version: 1\nview: standard\nauto_update: true\n" +
	"auto_update_level: major  # possible options: major, minor, patch\n" +
	"history_days: 365  # how far back history goes, 30 to 1825 days (5 years)\n" +
	"history_chunk_days: 100  # how many days back each run adds until history_days is reached, " +
	"1 to 365\n" +
	"working_hours: 8  # a working day is configured as this many hours, 1 to 24\n" +
	"dora_days: 30  # the window of the DORA numbers in days: 30, 90 or 180\n" +
	"issues_page: false  # the Issues page. " + pageValuesComment + "\n" +
	"days_page: false  # the Daily page. " + pageValuesComment + "\n" +
	"numbers_scoring_page: unlisted  # the Numbers and scoring page. " + pageValuesComment + "\n" +
	"history_page: unlisted  # the History page. " + pageValuesComment + "\n" +
	"tbd_page: true  # the Trunk-based development (TBD) page. " + pageValuesComment + "\n" +
	"projects: []\n"

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
	start := slices.Index(lines, "# version: 1")
	if start < 0 {
		t.Fatalf("want an example in the starter that starts at a line `# version: 1`, got:\n%s", Starter)
	}
	block := lines[start:]
	if end := slices.IndexFunc(block, func(l string) bool { return !strings.HasPrefix(l, "#") }); end >= 0 {
		block = block[:end]
	}
	var example []string
	for _, line := range block {
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
// projects, and with auto-merge on at major level (forsgren#58, #150).
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
	if !cfg.AutoUpdate || cfg.AutoUpdateLevel != LevelMajor {
		t.Errorf("want auto_update on at level major, got %v, %q", cfg.AutoUpdate, cfg.AutoUpdateLevel)
	}
	wantPageKeysWritten(t, cfg)
}

// wantPageKeysWritten (forsgren#159, #200, #285): the starter writes
// issues_page: false, days_page: false and numbers_scoring_page: unlisted
// itself (forsgren#55), so the settings page marks all three as set.
func wantPageKeysWritten(t *testing.T, cfg Config) {
	t.Helper()
	got := map[string]PageMode{"issues_page": cfg.IssuesPage, "days_page": cfg.DaysPage,
		"numbers_scoring_page": cfg.NumbersScoringPage}
	for key, want := range map[string]PageMode{"issues_page": PageOff, "days_page": PageOff,
		"numbers_scoring_page": PageUnlisted} {
		if got[key] != want || !cfg.written[key] {
			t.Errorf("want %s %v and written, got %v, written %v", key, want, got[key], cfg.written[key])
		}
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
	// A new installation starts with its view marked in the menu (forsgren#51, #128).
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

// TestStarterSaysNothingChecksAReleaseAgainstTheInstallationsData: the
// comment on the major default states the limit of the safeguards, so a
// person who keeps the default knows what is not checked (forsgren#150).
func TestStarterSaysNothingChecksAReleaseAgainstTheInstallationsData(t *testing.T) {
	text := strings.Join(strings.Fields(strings.ReplaceAll(Starter, "\n# ", " ")), " ")
	const want = "Nothing checks a release against this installation's own data."
	if !strings.Contains(text, want) {
		t.Errorf("want the starter to say %q", want)
	}
}

// TestStarterWritesDoraDaysAndLoadsClean (forsgren#178): the starter writes
// dora_days: 30, which loads with nothing rejected and shows on the settings
// as written, not the default.
func TestStarterWritesDoraDaysAndLoadsClean(t *testing.T) {
	got, err := parse([]byte(Starter))
	if err != nil || len(got.Rejected) != 0 {
		t.Fatalf("want the starter to load with nothing rejected, got %v, %v", got.Rejected, err)
	}
	want := Setting{Key: "dora_days", Value: "30", Default: "30", Set: true}
	if !slices.Contains(got.Settings(), want) {
		t.Errorf("want the settings to hold %+v, got %+v", want, got.Settings())
	}
}

// historyPageLine is the starter's history_page line (forsgren#68, #200).
const historyPageLine = "history_page: unlisted  # the History page. " + pageValuesComment

// TestStarterWritesHistoryPageUnlisted (forsgren#68, #199, #200): the starter
// writes history_page: unlisted right after numbers_scoring_page, with its
// comment.
func TestStarterWritesHistoryPageUnlisted(t *testing.T) {
	lines := starterLines()
	i := slices.IndexFunc(lines, func(l string) bool { return strings.HasPrefix(l, "numbers_scoring_page:") })
	if i < 0 || slices.Index(lines, historyPageLine) != i+1 {
		t.Errorf("want the line %q right after numbers_scoring_page in the starter", historyPageLine)
	}
}

// tbdPageLine is the starter's tbd_page line (forsgren#253).
const tbdPageLine = "tbd_page: true  # the Trunk-based development (TBD) page. " + pageValuesComment

// TestStarterWritesTbdPageOn (forsgren#253, forsgren#409): the starter writes
// tbd_page: true right after history_page, with its comment.
func TestStarterWritesTbdPageOn(t *testing.T) {
	lines := starterLines()
	i := slices.Index(lines, historyPageLine)
	if i < 0 || slices.Index(lines, tbdPageLine) != i+1 {
		t.Errorf("want the line %q right after history_page in the starter", tbdPageLine)
	}
}

// TestEveryPageKeyOfTheStarterExplainsTheThreeValues (forsgren#200): the
// comment of each of the four page keys ends in the same sentence on true,
// unlisted and false.
func TestEveryPageKeyOfTheStarterExplainsTheThreeValues(t *testing.T) {
	for _, key := range []string{"issues_page:", "days_page:", "numbers_scoring_page:", "history_page:", "tbd_page:"} {
		i := slices.IndexFunc(starterLines(), func(l string) bool { return strings.HasPrefix(l, key) })
		if i < 0 || !strings.HasSuffix(starterLines()[i], pageValuesComment) {
			t.Errorf("want the %s line of the starter to end in %q", key, pageValuesComment)
		}
	}
}

// TestStarterLoadsWithTheHistoryAndNumbersScoringPagesUnlisted (forsgren#68,
// #199, #200): the config the starter loads to reads both pages as unlisted,
// written, with no setting rejected.
func TestStarterLoadsWithTheHistoryAndNumbersScoringPagesUnlisted(t *testing.T) {
	cfg, err := parse([]byte(Starter))
	if err != nil || len(cfg.Rejected) != 0 {
		t.Fatalf("want nothing rejected, got %v, %v", cfg.Rejected, err)
	}
	for key, got := range map[string]PageMode{"history_page": cfg.HistoryPage,
		"numbers_scoring_page": cfg.NumbersScoringPage} {
		if got != PageUnlisted || !cfg.written[key] {
			t.Errorf("want %s unlisted and written, got %v, %v", key, got, cfg.written[key])
		}
	}
}
