package needs

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

// TestMissingReportsAFileNeedThatIsNotInTheCheckout (forsgren#73): a need of
// kind file is in place when the file is in the installation's checkout, and
// missing when it is not.
func TestMissingReportsAFileNeedThatIsNotInTheCheckout(t *testing.T) {
	const path = ".github/workflows/forsgren-update.yml"
	need := Need{Version: "0.3.8", Kind: "file", File: path}
	cases := []struct {
		name    string
		present bool
		want    []Need
	}{
		{"absent", false, []Need{need}},
		{"present", true, nil},
	}
	for _, c := range cases {
		root := t.TempDir()
		if c.present {
			writeFile(t, root, path)
		}
		got := Missing([]Need{need}, Installation{Root: root})
		if !reflect.DeepEqual(got, c.want) {
			t.Errorf("%s: want missing %v, got %v", c.name, c.want, got)
		}
	}
}

// writeFile writes a small file at the relative path rel under root, with its
// directories.
func writeFile(t *testing.T, root, rel string) {
	t.Helper()
	full := filepath.Join(root, rel)
	if err := os.MkdirAll(filepath.Dir(full), 0o750); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(full, []byte("name: update\n"), 0o600); err != nil {
		t.Fatal(err)
	}
}
