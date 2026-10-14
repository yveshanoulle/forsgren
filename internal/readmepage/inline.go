package readmepage

import (
	"errors"
	"fmt"
	"html"
	"strings"
)

// renderer renders the inline Markdown of the README, with its relative
// links made absolute against base.
type renderer struct {
	base string
}

// inlineRule renders the construct s starts with, and returns how many bytes
// it consumed; zero means s does not start with that construct.
type inlineRule func(r renderer, s string) (out string, used int, err error)

// inlineRules are tried in order at every position of the text.
func inlineRules() []inlineRule {
	return []inlineRule{renderer.code, renderer.bold, renderer.italic, renderer.link, renderer.autolink, renderer.image}
}

// inline renders the inline Markdown of text, escaping everything else.
func (r renderer) inline(text string) (string, error) {
	var out strings.Builder
	for i := 0; i < len(text); {
		rendered, used, err := r.firstRule(text[i:])
		if err != nil {
			return "", err
		}
		if used == 0 {
			rendered, used = html.EscapeString(text[i:i+1]), 1
		}
		out.WriteString(rendered)
		i += used
	}
	return out.String(), nil
}

// firstRule applies the first rule that matches the start of s.
func (r renderer) firstRule(s string) (out string, used int, err error) {
	for _, rule := range inlineRules() {
		out, used, err = rule(r, s)
		if err != nil || used > 0 {
			return out, used, err
		}
	}
	return "", 0, nil
}

// span cuts open + inner + closing off the start of s, where inner is not
// empty, and returns inner and how many bytes the span takes; zero means s
// does not start with such a span.
func span(s, open, closing string) (inner string, used int) {
	if !strings.HasPrefix(s, open) {
		return "", 0
	}
	end := strings.Index(s[len(open):], closing)
	if end <= 0 {
		return "", 0
	}
	return s[len(open) : len(open)+end], len(open) + end + len(closing)
}

// delimited renders s = open + inner + closing, where inner is not empty,
// with tag around the inner text rendered as inline Markdown.
func (r renderer) delimited(s, open, closing, tag string) (string, int, error) {
	text, used := span(s, open, closing)
	if used == 0 {
		return "", 0, nil
	}
	inner, err := r.inline(text)
	return "<" + tag + ">" + inner + "</" + tag + ">", used, err
}

// code renders a code span, whose text is never read as Markdown.
func (r renderer) code(s string) (string, int, error) {
	text, used := span(s, "`", "`")
	if used == 0 {
		return "", 0, nil
	}
	return "<code>" + html.EscapeString(text) + "</code>", used, nil
}

// bold renders **text**.
func (r renderer) bold(s string) (string, int, error) {
	return r.delimited(s, "**", "**", "strong")
}

// italic renders *text*.
func (r renderer) italic(s string) (string, int, error) {
	return r.delimited(s, "*", "*", "em")
}

// link renders [text](target), the target made absolute.
func (r renderer) link(s string) (string, int, error) {
	text, target, used := linkParts(s)
	if used == 0 {
		return "", 0, nil
	}
	href, err := r.resolve(target)
	if err != nil {
		return "", 0, err
	}
	inner, err := r.inline(text)
	return anchor(href, inner), used, err
}

// linkParts cuts [text](target) off the start of s, and returns how many
// bytes the link takes; zero means s does not start with a link. Text with a
// bracket in it, and a target with a space, are not a link.
func linkParts(s string) (text, target string, used int) {
	if !strings.HasPrefix(s, "[") {
		return "", "", 0
	}
	text, rest, found := strings.Cut(s[1:], "](")
	target, _, closed := strings.Cut(rest, ")")
	if !found || !closed {
		return "", "", 0
	}
	if !plainLink(text, target) {
		return "", "", 0
	}
	return text, target, len("[") + len(text) + len("](") + len(target) + len(")")
}

// plainLink is true for link text with no bracket and a target with no space.
func plainLink(text, target string) bool {
	return !strings.ContainsAny(text, "[]") && !strings.ContainsAny(target, " \n")
}

// autolink renders <https://…>.
func (r renderer) autolink(s string) (string, int, error) {
	if !strings.HasPrefix(s, "<https://") {
		return "", 0, nil
	}
	target, _, closed := strings.Cut(s[1:], ">")
	if !closed {
		return "", 0, nil
	}
	return anchor(target, html.EscapeString(target)), len("<") + len(target) + len(">"), nil
}

// anchor is a link to href around the rendered inner HTML.
func anchor(href, inner string) string {
	return "<a href=\"" + html.EscapeString(href) + "\">" + inner + "</a>"
}

// image refuses ![alt](src): the starter page has no images.
func (r renderer) image(s string) (string, int, error) {
	if strings.HasPrefix(s, "![") {
		return "", 0, errors.New("unsupported Markdown, an image: " + s)
	}
	return "", 0, nil
}

// resolve makes a link target absolute: an https link and a #anchor stay, a
// path relative to the README becomes a link into the repository at base.
// Any other scheme, a path above the repository and a root-relative path are
// errors, never links.
func (r renderer) resolve(target string) (string, error) {
	path := strings.TrimPrefix(target, "./")
	switch {
	case path == "":
		return "", errors.New("a link with no target")
	case strings.HasPrefix(path, "https://"), strings.HasPrefix(path, "#"):
		return path, nil
	case leavesTheRepository(path):
		return "", fmt.Errorf("a link that is neither https, an anchor nor a path in the repository: %q", target)
	}
	return r.base + path, nil
}

// leavesTheRepository is true for a path that is root-relative, climbs out of
// the repository, or starts with a scheme other than https.
func leavesTheRepository(path string) bool {
	first, _, _ := strings.Cut(path, "/")
	return strings.HasPrefix(path, "/") || first == ".." || strings.Contains(first, ":")
}
