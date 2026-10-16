package readmepage

import (
	"regexp"
	"strings"
	"testing"
)

// descriptionTag matches the page's meta description and captures its content.
var descriptionTag = regexp.MustCompile(`<meta name="description" content="([^"]*)">`)

// TestRenderDescribesThePageWithTheFirstParagraphAsPlainText (forsgren#201,
// step 1): the page carries exactly one meta description, and it is the
// README's first paragraph as plain text: the Markdown marks and links are
// gone, the lines are joined by single spaces, and the text is escaped.
func TestRenderDescribesThePageWithTheFirstParagraphAsPlainText(t *testing.T) {
	src := "# Widget\n\nA **bold** word, a [link](docs/guide.md) and `code`,\nfish & \"chips\".\n\nSecond paragraph.\n"
	got, err := Render(src, fixtureBase)
	if err != nil {
		t.Fatalf("Render: %v", err)
	}
	if n := strings.Count(got, `name="description"`); n != 1 {
		t.Fatalf("want exactly one meta description, got %d in:\n%s", n, got)
	}
	found := descriptionTag.FindStringSubmatch(got)
	if found == nil {
		t.Fatalf("want a well-formed meta description, got:\n%s", got)
	}
	want := "A bold word, a link and code, fish &amp; &#34;chips&#34;."
	if found[1] != want {
		t.Errorf("want the description %q, got %q", want, found[1])
	}
}

// TestRenderCutsALongDescriptionAtAWordWithAnEllipsis (forsgren#201, step 2):
// a first paragraph of up to 160 characters is the description as it is; a
// longer one is cut at a word boundary and ends in "…", the whole description
// at most 160 characters, counted in runes. One word longer than the limit has
// no boundary to cut at, so it is cut at the limit.
func TestRenderCutsALongDescriptionAtAWordWithAnEllipsis(t *testing.T) {
	words := func(n int) string { return strings.TrimSpace(strings.Repeat("abcd ", n)) }
	cases := []struct{ name, paragraph, want string }{
		{"exactly 160 characters", words(31) + " abcde", words(31) + " abcde"},
		{"161 characters", words(31) + " abcdef", words(31) + "…"},
		{"a break right at the limit", strings.Repeat("a", 158) + " bcd", strings.Repeat("a", 158) + "…"},
		{"one word longer than the limit", strings.Repeat("a", 200), strings.Repeat("a", 159) + "…"},
		{"multi-byte characters", strings.Repeat("é", 100) + " " + strings.Repeat("ü", 100), strings.Repeat("é", 100) + "…"},
	}
	for _, c := range cases {
		got, err := Render("# T\n\n"+c.paragraph+"\n", fixtureBase)
		if err != nil {
			t.Fatalf("%s: Render: %v", c.name, err)
		}
		found := descriptionTag.FindStringSubmatch(got)
		if found == nil {
			t.Fatalf("%s: want a meta description, got:\n%s", c.name, got)
		}
		if found[1] != c.want {
			t.Errorf("%s: want the description %q, got %q", c.name, c.want, found[1])
		}
	}
}
