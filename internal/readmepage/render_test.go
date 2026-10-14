package readmepage

import (
	"errors"
	"regexp"
	"strings"
	"testing"

	site "github.com/yveshanoulle/forsgren/internal/page"
)

const fixtureBase = "https://github.com/acme/widget/blob/main/"

const fixtureReadme = "# Widget\n" +
	"\n" +
	"A **[bold link](docs/guide.md#setup)** to the guide, a *plain* word, the\n" +
	"[licence](LICENSE), [contributing](./CONTRIBUTING.md), [the site](https://example.org/a?b=1&c=2),\n" +
	"<https://example.org/auto>, a [section](#usage) and the `forsgren.config.yml` file.\n" +
	"\n" +
	"## Usage\n" +
	"\n" +
	"- first [item](agent-installer.md): with a `code span`\n" +
	"  that continues on a second line\n" +
	"- second item\n"

// TestRenderMakesEveryLinkAbsoluteAndKeepsTheContent (forsgren#132): the
// page's title is the README's first heading, a relative link of every kind
// becomes a link into the repository at base, and no relative href is left.
func TestRenderMakesEveryLinkAbsoluteAndKeepsTheContent(t *testing.T) {
	got, err := Render(fixtureReadme, fixtureBase)
	if err != nil {
		t.Fatalf("Render: %v", err)
	}
	wants := []string{
		"<title>Widget</title>",
		`<h1 id="widget">Widget</h1>`,
		`<h2 id="usage">Usage</h2>`,
		`<strong><a href="https://github.com/acme/widget/blob/main/docs/guide.md#setup">bold link</a></strong>`,
		`<em>plain</em>`,
		`<a href="https://github.com/acme/widget/blob/main/LICENSE">licence</a>`,
		`<a href="https://github.com/acme/widget/blob/main/CONTRIBUTING.md">contributing</a>`,
		`<a href="https://example.org/a?b=1&amp;c=2">the site</a>`,
		`<a href="https://example.org/auto">https://example.org/auto</a>`,
		`<a href="#usage">section</a>`,
		`<code>forsgren.config.yml</code>`,
		"<ul>",
		`<li>first <a href="https://github.com/acme/widget/blob/main/agent-installer.md">item</a>: with a ` +
			"<code>code span</code>\nthat continues on a second line</li>",
		"<li>second item</li>",
	}
	for _, want := range wants {
		if !strings.Contains(got, want) {
			t.Errorf("the page lacks %q:\n%s", want, got)
		}
	}
	for _, href := range renderedPage(got).relativeHrefs() {
		t.Errorf("a relative href is left on the page: %q", href)
	}
}

// relativeHrefs are the links of the page that are neither https nor an
// anchor: the stylesheet link is a file of the page, not a link.
func (page renderedPage) relativeHrefs() []string {
	var relative []string
	for _, href := range regexp.MustCompile(`<a href="([^"]*)"`).FindAllStringSubmatch(string(page), -1) {
		if !strings.HasPrefix(href[1], "https://") && !strings.HasPrefix(href[1], "#") {
			relative = append(relative, href[1])
		}
	}
	return relative
}

// TestRenderRefusesWhatIsOutsideTheSubset (forsgren#132): a construct the
// renderer does not know, or a link that is not safe, is an error that names
// the reason, never a page that shows it wrong.
func TestRenderRefusesWhatIsOutsideTheSubset(t *testing.T) {
	const line, heading, link = "a line starting with", "unsupported heading", "neither https"
	cases := []struct{ name, src, reason string }{
		{"a fence", "# T\n\n```\ncode\n```\n", line},
		{"a quote", "# T\n\n> quoted\n", line},
		{"a table", "# T\n\n| a | b |\n", line},
		{"raw html", "# T\n\n<div>x</div>\n", line},
		{"a nested list", "# T\n\n- a\n    - b\n", line},
		{"an image", "# T\n\n![alt](a.png)\n", "an image"},
		{"a list line", "# T\n\n- a\nb\n", "unsupported list line"},
		{"a heading and text", "# T\nmore\n", heading},
		{"a deep heading", "# T\n\n#### Four\n", heading},
		{"a heading, no text", "# T\n\n#nospace\n", heading},
		{"a javascript link", "# T\n\n[x](javascript:alert(1))\n", link},
		{"a root link", "# T\n\n[x](/etc/passwd)\n", link},
		{"a link above", "# T\n\n[x](../other)\n", link},
		{"an http link", "# T\n\n[x](http://example.org)\n", link},
		{"a bad link in bold", "# T\n\n**[x](/root)**\n", link},
		{"a bad link in a heading", "# T [x](ftp://a)\n", link},
		{"a bad link in a list", "# T\n\n- [x](ftp://a)\n", link},
		{"an empty link", "# T\n\n[x]()\n", "no target"},
		{"no heading", "just words\n", "no heading"},
	}
	for _, c := range cases {
		got, err := Render(c.src, fixtureBase)
		if err == nil || !strings.Contains(err.Error(), c.reason) {
			t.Errorf("%s: want an error with %q, got %v and the page:\n%s", c.name, c.reason, err, got)
		}
	}
}

// TestRenderNamesTheLineOfWhatIsRefused (forsgren#158): a refusal says on
// which line of the README it is, whatever blank lines or CRLF come before.
func TestRenderNamesTheLineOfWhatIsRefused(t *testing.T) {
	cases := []struct {
		name, src string
		line      int
	}{
		{"a fence after a heading", "# T\n\n```\ncode\n```\n", 3},
		{"a quote in a later block", "# T\n\ntext\nmore\n\n> quoted\n", 6},
		{"the second line of a block", "# T\n\nfine\n| a | b |\n", 4},
		{"after a run of blank lines", "# T\n\n\n\n<div>x</div>\n", 5},
		{"CRLF line ends", "# T\r\n\r\n- a\r\n    - b\r\n", 4},
		{"a list line", "# T\n\n- a\n- b\nc\n", 3},
		{"a bad link", "# T\n\ntext\n\n[x](ftp://a)\n", 5},
	}
	for _, c := range cases {
		_, err := Render(c.src, fixtureBase)
		var refused *LineError
		if !errors.As(err, &refused) || refused.Line != c.line {
			t.Errorf("%s: want a LineError at line %d, got %v", c.name, c.line, err)
		}
	}
}

// TestRenderEscapesAndLeavesUnclosedMarkersAlone (forsgren#132): text is
// HTML-escaped, a code span is not read as Markdown, and a marker with no
// closing partner is plain text.
func TestRenderEscapesAndLeavesUnclosedMarkersAlone(t *testing.T) {
	src := "# A <b> & B\n\nx < y, `**not bold** <i>`, a * b, a ` c, [open and [b](x.md), <https://unclosed, [no close\n"
	got, err := Render(src, fixtureBase)
	if err != nil {
		t.Fatalf("Render: %v", err)
	}
	for _, want := range []string{
		"<title>A &lt;b&gt; &amp; B</title>",
		`<h1 id="a-b-b">A &lt;b&gt; &amp; B</h1>`,
		"x &lt; y, <code>**not bold** &lt;i&gt;</code>, a * b, a ` c,",
		`[open and <a href="https://github.com/acme/widget/blob/main/x.md">b</a>, `,
	} {
		if !strings.Contains(got, want) {
			t.Errorf("the page lacks %q:\n%s", want, got)
		}
	}
}

// TestRenderKeepsAQuoteInALinkTargetInsideTheHref (forsgren#158): a quote, a
// less-than or a greater-than sign in a link target, relative or absolute or
// in an autolink, comes out escaped, so the href attribute is never left and
// no attribute or tag is added to the page.
func TestRenderKeepsAQuoteInALinkTargetInsideTheHref(t *testing.T) {
	src := "# T\n\n[a](x\".md), [b](https://example.org/p\"onmouseover=\"x), " +
		"[c](https://example.org/<script>), <https://example.org/\"q>\n"
	got, err := Render(src, fixtureBase)
	if err != nil {
		t.Fatalf("Render: %v", err)
	}
	for _, want := range []string{
		`<a href="https://github.com/acme/widget/blob/main/x&#34;.md">a</a>`,
		`<a href="https://example.org/p&#34;onmouseover=&#34;x">b</a>`,
		`<a href="https://example.org/&lt;script&gt;">c</a>`,
		`<a href="https://example.org/&#34;q">https://example.org/&#34;q</a>`,
	} {
		if !strings.Contains(got, want) {
			t.Errorf("the page lacks %q:\n%s", want, got)
		}
	}
	for _, bad := range renderedPage(got).anchorsHoldingMoreThanHref() {
		t.Errorf("an anchor tag holds more than its href: %s", bad)
	}
}

// anchorsHoldingMoreThanHref are the opening anchor tags of the page that are
// not exactly an href without a quote or angle bracket inside, and a script tag.
func (page renderedPage) anchorsHoldingMoreThanHref() (bad []string) {
	tag := regexp.MustCompile(`^<a href="[^"<>]*">$`)
	for _, open := range regexp.MustCompile(`<a [^>]*>`).FindAllString(string(page), -1) {
		if !tag.MatchString(open) {
			bad = append(bad, open)
		}
	}
	if strings.Contains(string(page), "<script") {
		bad = append(bad, "a script tag")
	}
	return bad
}

// ruleBodies are the bodies of the rules of css whose selector, at the start
// of a line, is selector.
func ruleBodies(css, selector string) (bodies []string) {
	rule := regexp.MustCompile(`(?s)(?:^|\n)` + regexp.QuoteMeta(selector) + `\s*\{([^}]*)\}`)
	for _, r := range rule.FindAllStringSubmatch(css, -1) {
		bodies = append(bodies, r[1])
	}
	return bodies
}

// holds tells whether one of bodies holds declaration, "property: value",
// with any space after the colon.
func holds(bodies []string, declaration string) bool {
	property, value, _ := strings.Cut(declaration, ": ")
	pattern := regexp.MustCompile(regexp.QuoteMeta(property) + `:\s*` + regexp.QuoteMeta(value) + `;`)
	for _, body := range bodies {
		if pattern.MatchString(body) {
			return true
		}
	}
	return false
}

// TestStarterPageIsSeventyTwoRemWideWhileTheMetricsPagesKeepTheirCap
// (forsgren#153, step 2; decision #160): forsgren.be is 150% of the 48rem it
// had, 72rem, through a class on its body that the shared stylesheet styles,
// while the plain body rule (the metrics pages) keeps its own, wider cap.
func TestStarterPageIsSeventyTwoRemWideWhileTheMetricsPagesKeepTheirCap(t *testing.T) {
	got, err := Render(fixtureReadme, fixtureBase)
	if err != nil {
		t.Fatalf("Render: %v", err)
	}
	if !strings.Contains(got, `<body class="starter">`) {
		t.Errorf("want the starter page's body to carry class starter, got:\n%s", got)
	}
	css := string(site.Styles())
	if !holds(ruleBodies(css, "body.starter"), "max-width: 72rem") {
		t.Errorf("want a body.starter rule with max-width: 72rem in styles.css, got:\n%s", css)
	}
	if !holds(ruleBodies(css, "body"), "max-width: 120rem") {
		t.Errorf("want the plain body rule to keep max-width: 120rem, got:\n%s", css)
	}
}

// TestStarterPageIsAFramedCard (forsgren#153, step 2b; decision #161): under
// body.starter the main is a card: a thin border in the text colour (the
// colour every table line already uses, so no new colour), rounded corners and
// 2rem of inner padding; the body's 1rem padding is the gutter outside it.
func TestStarterPageIsAFramedCard(t *testing.T) {
	css := string(site.Styles())
	cards := ruleBodies(css, "body.starter main")
	if len(cards) == 0 {
		t.Fatalf("want a body.starter main rule in styles.css, got:\n%s", css)
	}
	for _, want := range []string{"border: 1px solid currentcolor;", "border-radius:", "padding: 2rem;"} {
		if !strings.Contains(cards[0], want) {
			t.Errorf("want the body.starter main rule to hold %q, got:\n%s", want, cards[0])
		}
	}
	if regexp.MustCompile(`#[0-9a-fA-F]{3,6}|rgb|hsl`).MatchString(cards[0]) {
		t.Errorf("want no new colour in the frame, got:\n%s", cards[0])
	}
	if !holds(ruleBodies(css, "body"), "padding: 1rem") {
		t.Errorf("want the body to keep its 1rem padding as the gutter around the frame, got:\n%s", css)
	}
}

// renderedPage is the HTML page Render returns.
type renderedPage string
