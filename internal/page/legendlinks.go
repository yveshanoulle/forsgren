package page

import (
	"regexp"
	"slices"
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/yveshanoulle/forsgren/internal/dictionary"
)

// withEntryLinks is doc with the links to the Dictionary page its kind of page
// carries: the legend links the entries it mentions (forsgren#370, step 3).
func withEntryLinks(doc string, p page) (string, error) {
	if p.file != "legend.html" {
		return doc, nil
	}
	entries, err := dictionary.Entries()
	if err != nil {
		return doc, err
	}
	return linkEntries(doc, p.base, entries), nil
}

// linkEntries is doc with the first mention of each entry in each section of
// its main element linked to the entry on the Dictionary page, base before
// "dictionary.html". A section is the text under one h2, or before the first.
// A mention is one of the entry's labels (dictionary.Entry.Labels), a whole
// word written exactly as the label is, the longest label first, so a shorter
// label does not take words from a longer one. Nothing is linked inside a
// heading or inside a link, or outside main. The links come from the entries,
// so a renamed entry cannot leave a dead one.
func linkEntries(doc, base string, entries []dictionary.Entry) string {
	l := &linker{base: base, labels: labelsOf(entries), seen: map[string]bool{}}
	var out strings.Builder
	for rest := markup(doc); rest != ""; {
		text, tag, after := splitTag(rest)
		out.WriteString(string(l.text(text)))
		out.WriteString(string(tag))
		l.note(tag)
		rest = after
	}
	return out.String()
}

// markup is a piece of a page's HTML: text, or one tag.
type markup string

// splitTag cuts s into the text before its first tag, the tag, and the rest.
// A "<" with no ">" after it is text.
func splitTag(s markup) (text, tag, rest markup) {
	start := strings.IndexByte(string(s), '<')
	if start < 0 {
		return s, "", ""
	}
	end := strings.IndexByte(string(s[start:]), '>')
	if end < 0 {
		return s, "", ""
	}
	return s[:start], s[start : start+end+1], s[start+end+1:]
}

// label is a way the pages write an entry.
type label struct{ text, anchor string }

// labelsOf are the labels of the entries, the longest first.
func labelsOf(entries []dictionary.Entry) []label {
	var labels []label
	for _, e := range entries {
		for _, text := range e.Labels() {
			labels = append(labels, label{text, e.Anchor()})
		}
	}
	slices.SortStableFunc(labels, func(a, b label) int { return len(b.text) - len(a.text) })
	return labels
}

// linker walks a page's text and tags in order.
type linker struct {
	base   string
	labels []label
	// seen are the anchors linked in the section so far.
	seen map[string]bool
	// inMain is true between <main> and </main>.
	inMain bool
	// skipping counts the open headings and links, where nothing is linked.
	skipping int
}

// tagName matches the start of a tag: whether it closes, and its name.
var tagName = regexp.MustCompile(`^<(/?)([a-zA-Z][a-zA-Z0-9]*)`)

// headingName matches the names of the heading tags.
var headingName = regexp.MustCompile(`^h[1-6]$`)

// note takes a tag into account: main, headings and links open and close, and
// an h2 starts a section.
func (l *linker) note(tag markup) {
	m := tagName.FindStringSubmatch(string(tag))
	if m == nil {
		return
	}
	closing, name := m[1] == "/", strings.ToLower(m[2])
	l.countSkipping(name, closing)
	switch {
	case name == "main":
		l.inMain = !closing
	case name == "h2" && !closing:
		clear(l.seen)
	}
}

// countSkipping counts the headings and links that are open.
func (l *linker) countSkipping(name string, closing bool) {
	if name == "a" || headingName.MatchString(name) {
		l.skipping = max(0, l.skipping+step(closing))
	}
}

// step is -1 for a closing tag and 1 for an opening one.
func step(closing bool) int {
	if closing {
		return -1
	}
	return 1
}

// text is s with the first mention of each entry of the section linked.
func (l *linker) text(s markup) markup {
	if !l.inMain || l.skipping > 0 {
		return s
	}
	var out strings.Builder
	for i := 0; i < len(s); {
		if found, ok := l.mentionAt(s, i); ok {
			out.WriteString(l.link(found))
			i += len(found.text)
			continue
		}
		_, size := utf8.DecodeRuneInString(string(s[i:]))
		out.WriteString(string(s[i : i+size]))
		i += size
	}
	return markup(out.String())
}

// link is the label as written, linked unless its entry is linked in the
// section already.
func (l *linker) link(found label) string {
	if l.seen[found.anchor] {
		return found.text
	}
	l.seen[found.anchor] = true
	return `<a href="` + l.base + `dictionary.html#` + found.anchor + `">` + found.text + `</a>`
}

// mentionAt is the label s holds at i as a whole word, the longest first.
func (l *linker) mentionAt(s markup, i int) (label, bool) {
	if before, _ := utf8.DecodeLastRuneInString(string(s[:i])); inWord(before) {
		return label{}, false
	}
	for _, candidate := range l.labels {
		rest, ok := strings.CutPrefix(string(s[i:]), candidate.text)
		if after, _ := utf8.DecodeRuneInString(rest); ok && !inWord(after) {
			return candidate, true
		}
	}
	return label{}, false
}

// inWord is a letter, a digit, a hyphen or an underscore: trunk-based is not
// a mention of trunk. The error rune, what no text before or after gives, is
// none of them.
func inWord(r rune) bool {
	return unicode.IsLetter(r) || unicode.IsDigit(r) || r == '-' || r == '_'
}
