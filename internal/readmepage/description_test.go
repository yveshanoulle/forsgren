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
