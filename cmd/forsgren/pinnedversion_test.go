package main

import (
	"fmt"
	"io/fs"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"testing"
)

// pinnedVersion matches the value of var version in main.go, or the patch
// release after it, as a whole version.
func pinnedVersion(t *testing.T) *regexp.Regexp {
	t.Helper()
	m := regexp.MustCompile(`(?m)^var version = "(\d+)\.(\d+)\.(\d+)"`).FindSubmatch([]byte(readFile(t, "main.go")))
	if m == nil {
		t.Fatal("want var version in main.go")
	}
	patch, _ := strconv.Atoi(string(m[3]))
	current := fmt.Sprintf("%s.%s.%s", m[1], m[2], m[3])
	next := fmt.Sprintf("%s.%s.%d", m[1], m[2], patch+1)
	return regexp.MustCompile(`(^|[^0-9])(` + regexp.QuoteMeta(current) + `|` +
		regexp.QuoteMeta(next) + `)($|[^0-9]|\.($|[^0-9]))`)
}

// testFiles are the test files and golden pages of the repository.
func testFiles(t *testing.T) []string {
	t.Helper()
	var files []string
	err := filepath.WalkDir("../..", func(file string, entry fs.DirEntry, err error) error {
		switch {
		case err != nil:
			return err
		case entry.IsDir() && slices.Contains([]string{".git", ".claude", "node_modules"}, entry.Name()):
			return filepath.SkipDir
		case strings.HasSuffix(file, "_test.go"), strings.HasSuffix(file, ".golden.html"):
			files = append(files, file)
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	return files
}

// TestNoTestPinsTheReleasedVersion (forsgren#237, step 3): no test file and
// no golden page names the value of var version or the patch release after it,
// so a release changes none of them. The tests render as a fixed version.
func TestNoTestPinsTheReleasedVersion(t *testing.T) {
	pinned := pinnedVersion(t)
	for _, file := range testFiles(t) {
		if found := pinned.FindStringSubmatch(readFile(t, file)); found != nil {
			t.Errorf("%s names %s, the released version or the next one; use the test version",
				strings.TrimPrefix(file, "../../"), found[2])
		}
	}
}
