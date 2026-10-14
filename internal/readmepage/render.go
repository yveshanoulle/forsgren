// Package readmepage renders README.md to the one HTML page forsgren.be shows
// (forsgren#132). It reads the small subset of Markdown the README is written
// in, and refuses everything else, so a README that grows a construct this
// package does not know fails the page build instead of publishing it wrong.
//
// The subset: headings (# to ###), paragraphs, one-level bullet lists with
// indented continuation lines, and inline code spans, bold, italic, links,
// <autolinks> and nothing more. A relative link becomes a link into the
// repository at the base URL; an absolute https link and a #anchor stay.
package readmepage

import (
	"errors"
	"fmt"
	"html"
	"regexp"
	"strings"
)

// Render renders the Markdown src to a complete HTML page, with every
// relative link made absolute against base (an https URL ending in a slash).
// The page's title is the text of the first heading; a README without a
// heading, or with a construct outside the subset, is an error.
func Render(src, base string) (string, error) {
	r := renderer{base: base}
	var body []string
	title := ""
	for _, block := range splitBlocks(src) {
		out, heading, err := r.block(block.text)
		if err != nil {
			return "", atLine(err, block.line)
		}
		if title == "" && heading != "" {
			title = heading
		}
		body = append(body, out)
	}
	if title == "" {
		return "", errors.New("the README has no heading to title the page")
	}
	return page(title, strings.Join(body, "\n")), nil
}

// LineError is a refusal of the README at a line, 1-based: within the block
// while a block is rendered, within the README once Render returns it.
type LineError struct {
	Line int
	Msg  string
}

func (e *LineError) Error() string { return fmt.Sprintf("line %d: %s", e.Line, e.Msg) }

// page wraps the rendered body in the page's document.
func page(title, body string) string {
	return "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n" +
		"<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n" +
		"<title>" + html.EscapeString(title) + "</title>\n" +
		"<link rel=\"stylesheet\" href=\"styles.css\">\n</head>\n<body class=\"starter\">\n<main>\n" +
		body + "\n</main>\n</body>\n</html>\n"
}

// atLine tells where err is: a LineError holds its line within the block and
// is moved to the block's first line, any other error is put at that line.
func atLine(err error, first int) error {
	var inBlock *LineError
	if errors.As(err, &inBlock) {
		return &LineError{Line: first + inBlock.Line - 1, Msg: inBlock.Msg}
	}
	return &LineError{Line: first, Msg: err.Error()}
}

// textBlock is a block of lines, and the line of the README it starts at (1-based).
type textBlock struct {
	text string
	line int
}

// splitBlocks cuts src into blocks of lines, separated by blank lines.
func splitBlocks(src string) []textBlock {
	var blocks []textBlock
	line := 1
	for _, block := range strings.Split(strings.ReplaceAll(src, "\r\n", "\n"), "\n\n") {
		if strings.TrimSpace(block) != "" {
			blocks = append(blocks, textBlock{strings.TrimRight(block, "\n"), line})
		}
		line += strings.Count(block, "\n") + 2
	}
	return blocks
}

// unsupportedStarts are the line starts of Markdown constructs outside the
// subset: a fence, a quote, a table, a rule, an ordered or starred list, an
// indented code block and raw HTML.
var unsupportedStarts = []string{"```", "~~~", ">", "|", "---", "***", "1.", "* ", "+ ", "    ", "\t", "<"}

// block renders one block, and returns the heading's text when it is one.
func (r renderer) block(block string) (out, heading string, err error) {
	for i, line := range strings.Split(block, "\n") {
		if start, bad := unsupported(line); bad {
			msg := fmt.Sprintf("unsupported Markdown, a line starting with %q: %s", start, line)
			return "", "", &LineError{Line: i + 1, Msg: msg}
		}
	}
	switch {
	case strings.HasPrefix(block, "#"):
		return r.heading(block)
	case strings.HasPrefix(block, "- "):
		out, err = r.list(block)
		return out, "", err
	}
	out, err = r.inline(block)
	return "<p>" + out + "</p>", "", err
}

// unsupported reports the construct a line starts with when it is outside the
// subset. A line of a paragraph that begins with <https:// is an autolink and
// stays.
func unsupported(line string) (string, bool) {
	for _, start := range unsupportedStarts {
		if strings.HasPrefix(line, start) && !strings.HasPrefix(line, "<https://") {
			return start, true
		}
	}
	return "", false
}

// heading renders a one-line heading of level 1 to 3.
func (r renderer) heading(block string) (out, heading string, err error) {
	hashes, text, found := strings.Cut(block, " ")
	if !found || !isHeadingLine(hashes, block) {
		return "", "", fmt.Errorf("unsupported heading: %q", block)
	}
	inner, err := r.inline(text)
	if err != nil {
		return "", "", err
	}
	level := fmt.Sprint(len(hashes))
	return "<h" + level + " id=\"" + slug(text) + "\">" + inner + "</h" + level + ">", text, nil
}

// isHeadingLine is true for one line that starts with one to three hashes.
func isHeadingLine(hashes, block string) bool {
	if strings.Contains(block, "\n") {
		return false
	}
	return len(hashes) <= 3 && strings.Trim(hashes, "#") == ""
}

// nonAlphanumeric is what a slug collapses to a hyphen.
var nonAlphanumeric = regexp.MustCompile(`[^a-z0-9]+`)

// slug is the heading's anchor: lower case, letters and digits, the rest
// collapsed to single hyphens.
func slug(text string) string {
	return strings.Trim(nonAlphanumeric.ReplaceAllString(strings.ToLower(text), "-"), "-")
}

// list renders a bullet list.
func (r renderer) list(block string) (string, error) {
	items, err := listItems(block)
	if err != nil {
		return "", err
	}
	out := []string{"<ul>"}
	for _, item := range items {
		inner, err := r.inline(item)
		if err != nil {
			return "", err
		}
		out = append(out, "<li>"+inner+"</li>")
	}
	return strings.Join(append(out, "</ul>"), "\n"), nil
}

// listItems cuts a list into its items: an item starts with "- ", and a
// following line indented by two spaces continues it.
func listItems(block string) ([]string, error) {
	var items []string
	for _, line := range strings.Split(block, "\n") {
		switch {
		case strings.HasPrefix(line, "- "):
			items = append(items, line[2:])
		case strings.HasPrefix(line, "  ") && len(items) > 0:
			items[len(items)-1] += "\n" + strings.TrimLeft(line, " ")
		default:
			return nil, fmt.Errorf("unsupported list line: %q", line)
		}
	}
	return items, nil
}
