package readmepage

import (
	"html"
	"regexp"
	"strings"
)

// htmlTag is a tag in rendered HTML. Text is escaped before it is searched, so
// a "<" in the README is never mistaken for one.
var htmlTag = regexp.MustCompile(`<[^>]*>`)

// content is what the rendered blocks of a README add up to: the page's body,
// its title (the first heading) and its description (the first paragraph).
type content struct {
	title, description string
	body               []string
}

// add takes one rendered block, and the heading's text when it is a heading.
func (c *content) add(out, heading string) {
	if c.title == "" {
		c.title = heading
	}
	if c.description == "" && strings.HasPrefix(out, "<p>") {
		c.description = shorten(plainText(out), maxDescription)
	}
	c.body = append(c.body, out)
}

// plainText is rendered HTML as text: the tags stripped, the entities decoded
// and the lines joined by single spaces. The meta description reads from the
// README this way, so it cannot drift from it.
func plainText(rendered string) string {
	return strings.Join(strings.Fields(html.UnescapeString(htmlTag.ReplaceAllString(rendered, ""))), " ")
}

// maxDescription is the most characters a search engine shows of a page's
// description, the ellipsis of a cut one included.
const maxDescription = 160

// shorten cuts text to at most limit characters (runes, not bytes). A longer
// text is cut at the last word boundary that leaves room for the ellipsis "…"
// and ends in it; one word longer than the limit has no boundary and is cut at
// the limit.
func shorten(text string, limit int) string {
	runes := []rune(text)
	if len(runes) <= limit {
		return text
	}
	head := runes[:limit-1]
	if runes[limit-1] != ' ' {
		if space := strings.LastIndex(string(head), " "); space > 0 {
			head = []rune(string(head)[:space])
		}
	}
	return strings.TrimRight(string(head), " ") + "…"
}
