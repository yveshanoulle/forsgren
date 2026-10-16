package install

import (
	"regexp"
	"slices"
	"strings"
	"testing"
)

// wantIn fails the test for each of the words that text does not hold.
func wantIn(t *testing.T, what, text string, words ...string) {
	t.Helper()
	for _, word := range words {
		if !strings.Contains(text, word) {
			t.Errorf("want %q in %s, got %q", word, what, text)
		}
	}
}

// TestReadmeSaysItIsForsgrensFileNearTheTop: within its first lines the
// README says it is forsgren's file, for which version, and that a change is
// overwritten, in one line (forsgren#110).
func TestReadmeSaysItIsForsgrensFileNearTheTop(t *testing.T) {
	lines := strings.Split(readme, "\n")
	top := slices.IndexFunc(lines, func(line string) bool { return strings.Contains(line, "forsgren's file") })
	if top < 0 || top > 4 {
		t.Fatalf("want the ownership line within the first 5 lines, found at index %d", top)
	}
	wantIn(t, "the ownership line", lines[top], versionToken, "written by the daily run", "overwritten")
}

// placeholders are the {{...}} of text, whole ones.
func placeholders(text string) []string {
	return regexp.MustCompile(`\{\{[^}]*\}\}`).FindAllString(text, -1)
}

// openings are the "{{" and "}}" of text, which whole placeholders pair up.
func openings(text string) (int, int) {
	return strings.Count(text, "{{"), strings.Count(text, "}}")
}

// TestReadmeHoldsNoPlaceholderButTheVersion: every {{...}} is the version
// token, so Text leaves nothing behind for any version.
func TestReadmeHoldsNoPlaceholderButTheVersion(t *testing.T) {
	found := placeholders(readme)
	open, closing := openings(readme)
	if len(found) == 0 {
		t.Error("want the version token in the README")
	}
	if !slices.Equal([]int{open, closing}, []int{len(found), len(found)}) {
		t.Errorf("want only whole placeholders, got %d for %d openings, %d closings", len(found), open, closing)
	}
	other := slices.DeleteFunc(slices.Clone(found), func(s string) bool { return s == versionToken })
	if len(other) > 0 {
		t.Errorf("want only %s as a placeholder, got %v", versionToken, other)
	}
}

// datedVersions are the only version numbers the README may write out, each
// with the words it stands in: the Daily page note of 1.3.0 (twice, a fact
// about that release) and the example of the update levels. Any other number
// is a version that will go stale; the current one is the token.
var datedVersions = map[string]string{
	"1.3.0": "forsgren 1.3.0",
	"0.2.0": "`patch` (0.2.0 to 0.2.1)",
	"0.2.1": "`patch` (0.2.0 to 0.2.1)",
	"0.3.0": "`minor` (to 0.3.0)",
	"1.0.0": "`major` (to\n  1.0.0)",
}

// undated are the version numbers of text that datedVersions does not allow,
// in their words.
func undated(text string) []string {
	var out []string
	for _, v := range regexp.MustCompile(`\d+\.\d+\.\d+`).FindAllString(text, -1) {
		if words, ok := datedVersions[v]; !ok || !strings.Contains(text, words) {
			out = append(out, v)
		}
	}
	return out
}

// TestReadmeWritesNoVersionButTheDatedOnes: every x.y.z in the README is one
// of datedVersions, in its words, and no more of them than the six there are.
func TestReadmeWritesNoVersionButTheDatedOnes(t *testing.T) {
	if got := undated(readme); len(got) > 0 {
		t.Errorf("want no version literal but the dated ones, got %v", got)
	}
	if n := len(regexp.MustCompile(`\d+\.\d+\.\d+`).FindAllString(readme, -1)); n != 6 {
		t.Errorf("want exactly the 6 dated version numbers, got %d", n)
	}
}

// TestReadmeKeepsItsDatedNotes: the two notes on forsgren 1.3.0 are worded as
// pinned, so the rule above cannot be met by rewording one into another number.
func TestReadmeKeepsItsDatedNotes(t *testing.T) {
	wantIn(t, "the README", readme, "The Daily page is hidden by default (forsgren 1.3.0)",
		"Upgrading to forsgren 1.3.0 hides the Daily page")
}
