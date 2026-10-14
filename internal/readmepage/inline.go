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

// delimited renders s = open + inner + close, where inner is not empty, with
// wrap around the inner text rendered as inline Markdown.
func (r renderer) delimited(s, open, closing, tag string) (string, int, error) {
	if !strings.HasPrefix(s, open) {
		return "", 0, nil
	}
	end := strings.Index(s[len(open):], closing)
	if end <= 0 {
		return "", 0, nil
	}
	inner, err := r.inline(s[len(open) : len(open)+end])
	return "<" + tag + ">" + inner + "</" + tag + ">", len(open) + end + len(closing), err
}

// code renders a code span, whose text is never read as Markdown.
func (r renderer) code(s string) (string, int, error) {
	if !strings.HasPrefix(s, "`") {
		return "", 0, nil
	}
	end := strings.Index(s[1:], "`")
	if end <= 0 {
		return "", 0, nil
	}
	return "<code>" + html.EscapeString(s[1:1+end]) + "</code>", end + 2, nil
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
	text, target, ok := linkParts(s)
	if !ok {
		return "", 0, nil
	}
	href, err := r.resolve(target)
	if err != nil {
		return "", 0, err
	}
	inner, err := r.inline(text)
	return "<a href=\"" + html.EscapeString(href) + "\">" + inner + "</a>", 1 + len(text) + 2 + len(target) + 1, err
}

// linkParts cuts [text](target) off the start of s. Text with a bracket in
// it, and a target with a space, are not a link.
func linkParts(s string) (text, target string, ok bool) {
	if !strings.HasPrefix(s, "[") {
		return "", "", false
	}
	text, rest, found := strings.Cut(s[1:], "](")
	target, _, closed := strings.Cut(rest, ")")
	if !found || !closed {
		return "", "", false
	}
	return text, target, plainLink(text, target)
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
	return "<a href=\"" + html.EscapeString(target) + "\">" + html.EscapeString(target) + "</a>", len(target) + 2, nil
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
