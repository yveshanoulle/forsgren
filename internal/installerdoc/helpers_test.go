package installerdoc

import (
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/config"
)

// repoFile is a file named from the repository root.
type repoFile string

// installerFile is the agent installer.
const installerFile repoFile = "agent-installer.md"

// upgraderFile is the agent upgrader.
const upgraderFile repoFile = "agent-upgrade.md"

// deleterFile is the agent file that removes an installation.
const deleterFile repoFile = "agent-delete.md"

// readRepoFile returns a file named from the repository root. Reading
// through os.DirFS keeps every read inside the repository (gosec G304).
func readRepoFile(t *testing.T, path repoFile) string {
	t.Helper()
	b, err := fs.ReadFile(os.DirFS("../.."), string(path))
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	return string(b)
}

// readInstaller returns the agent installer.
func readInstaller(t *testing.T) string {
	t.Helper()
	return readRepoFile(t, installerFile)
}

// readUpgrader returns the agent upgrader.
func readUpgrader(t *testing.T) string {
	t.Helper()
	return readRepoFile(t, upgraderFile)
}

// readRepoFileAsOneLine returns a file named from the repository root with
// its wrapped lines joined into one, every run of whitespace a single space.
func readRepoFileAsOneLine(t *testing.T, path repoFile) string {
	t.Helper()
	return asOneLine(readRepoFile(t, path))
}

// asOneLine is text with its wrapped lines joined into one, every run of
// whitespace a single space.
func asOneLine(text string) string { return strings.Join(strings.Fields(text), " ") }

// section returns the text of the "## " section of the file at path whose
// heading starts with heading, from the heading line up to the next "## "
// heading (or the end).
func section(t *testing.T, path repoFile, heading string) string {
	t.Helper()
	lines := strings.Split(readRepoFile(t, path), "\n")
	start := -1
	for i, l := range lines {
		if start < 0 {
			if strings.HasPrefix(l, "## "+heading) {
				start = i
			}
			continue
		}
		if strings.HasPrefix(l, "## ") {
			return strings.Join(lines[start:i], "\n")
		}
	}
	if start < 0 {
		t.Fatalf("no section %q in %s", heading, path)
	}
	return strings.Join(lines[start:], "\n")
}

// upgraderSection is section of the agent upgrader, as one line.
func upgraderSection(t *testing.T, heading string) string {
	t.Helper()
	return asOneLine(section(t, upgraderFile, heading))
}

// deleterSection is section of the agent deleter, as one line.
func deleterSection(t *testing.T, heading string) string {
	t.Helper()
	return asOneLine(section(t, deleterFile, heading))
}

// wantAll reports each of wants that text does not contain.
func wantAll(t *testing.T, where, text string, wants ...string) {
	t.Helper()
	for _, want := range wants {
		if !strings.Contains(text, want) {
			t.Errorf("%s does not contain %q", where, want)
		}
	}
}

// workRemoval is a line of a file that runs `rm -r WORK`: its 1-based number
// and its text without surrounding space.
type workRemoval struct {
	line int
	text string
}

// workRemovals returns how many lines of the file at path run `rm -r WORK`,
// and those of them not directly preceded by `cd WORK/..`. An agent that
// removes the folder it works in raises Claude Code's dangerous-rm prompt.
func workRemovals(t *testing.T, path repoFile) (found int, notLeavingFirst []workRemoval) {
	t.Helper()
	lines := strings.Split(readRepoFile(t, path), "\n")
	for i, l := range lines {
		if !strings.Contains(l, "rm -r WORK") {
			continue
		}
		found++
		if i == 0 || strings.TrimSpace(lines[i-1]) != "cd WORK/.." {
			notLeavingFirst = append(notLeavingFirst, workRemoval{line: i + 1, text: strings.TrimSpace(l)})
		}
	}
	return found, notLeavingFirst
}

// starterLevel is the auto_update_level forsgren's own starter loads with.
func starterLevel(t *testing.T) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "forsgren.config.yml")
	if err := os.WriteFile(path, []byte(config.Starter), 0o600); err != nil {
		t.Fatal(err)
	}
	cfg, err := config.Load(path)
	if err != nil {
		t.Fatalf("want the starter to load, got %v", err)
	}
	return cfg.AutoUpdateLevel
}
