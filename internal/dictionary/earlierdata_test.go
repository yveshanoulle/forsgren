package dictionary

import (
	"strings"
	"testing"
)

// TestEarlierDataNotYetReadCoversTheServiceRows (forsgren#589): the … also
// marks a service or rule row with paths while the files of its pushed
// commits are being read, so the entry says so, and its From line names the
// mark that ends it as well as the push read's cut.
func TestEarlierDataNotYetReadCoversTheServiceRows(t *testing.T) {
	e := entryNamed(t, "Earlier data not yet read")
	for _, says := range []string{"page limit", "service or rule row with paths", "pushed commits",
		"1000 commits a run"} {
		if !strings.Contains(e.Definition, says) {
			t.Errorf("want the definition to say %q, got %q", says, e.Definition)
		}
	}
	for _, says := range []string{"data/pushes_cut.csv", "data/push_files_filled.csv"} {
		if !strings.Contains(e.From, says) {
			t.Errorf("want the From line to name %s, got %q", says, e.From)
		}
	}
}
