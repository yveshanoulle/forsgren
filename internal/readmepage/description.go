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
		c.description = plainText(out)
	}
	c.body = append(c.body, out)
}

// plainText is rendered HTML as text: the tags stripped, the entities decoded
// and the lines joined by single spaces. The meta description reads from the
// README this way, so it cannot drift from it.
func plainText(rendered string) string {
	return strings.Join(strings.Fields(html.UnescapeString(htmlTag.ReplaceAllString(rendered, ""))), " ")
}
