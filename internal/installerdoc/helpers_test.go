package installerdoc

import (
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/config"
)

// installerFile is the agent installer, named from the repository root.
const installerFile = "agent-installer.md"

// readRepoFile returns a file named from the repository root. Reading
// through os.DirFS keeps every read inside the repository (gosec G304).
func readRepoFile(t *testing.T, path string) string {
	t.Helper()
	b, err := fs.ReadFile(os.DirFS("../.."), path)
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

// readRepoFileAsOneLine returns a file named from the repository root with
// its wrapped lines joined into one, every run of whitespace a single space.
func readRepoFileAsOneLine(t *testing.T, path string) string {
	t.Helper()
	return asOneLine(readRepoFile(t, path))
}

// asOneLine is text with its wrapped lines joined into one, every run of
// whitespace a single space.
func asOneLine(text string) string { return strings.Join(strings.Fields(text), " ") }

// section returns the text of the "## " section whose heading starts with
// heading, from the heading line up to the next "## " heading (or the end).
func section(t *testing.T, doc, heading string) string {
	t.Helper()
	lines := strings.Split(doc, "\n")
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
		t.Fatalf("no section %q in %s", heading, installerFile)
	}
	return strings.Join(lines[start:], "\n")
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
