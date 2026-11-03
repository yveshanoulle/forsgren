package page

import (
	"regexp"
	"strings"
	"testing"
)

// forsgren#571: the legend links an entry's label wherever it stands, so a
// word the legend uses in its everyday sense must not be the label form. Each
// case names a sentence of the legend whose everyday word was once linked to
// the entry of the same word ("cut" the list, "mean" the verb).
func TestLegendDoesNotLinkAWordInItsEverydaySense(t *testing.T) {
	cases := []struct{ name, linkedAs string }{
		{"durations are cut down, never rounded up", `cut</a> down`},
		{"red and green mean rose and fell", `mean</a> rose and fell`},
		{"a dash does not mean deployment data is missing", `mean</a> deployment data is missing`},
		{"a marked date does not mean the repository started", `mean</a> the repository started`},
		{"major does not mean a major release is safe", `mean</a> a major release is safe`},
	}
	all := strings.Join(legendSections(t), "")
	for _, c := range cases {
		if regexp.MustCompile(`<a [^>]*>` + regexp.QuoteMeta(c.linkedAs)).MatchString(all) {
			t.Errorf("%s: the everyday word is linked to the Dictionary: %s", c.name, c.linkedAs)
		}
	}
}
