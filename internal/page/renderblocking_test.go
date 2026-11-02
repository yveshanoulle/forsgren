package page

import (
	"strings"
	"testing"
)

// pageEnd is the id the head's render-blocking link waits for (forsgren#558).
const pageEnd = "page-end"

// TestEveryPageWaitsForItsEndBeforeTheFirstPaint (forsgren#558): a browser
// may paint a page while its parser is still inside a table; the rows parsed
// after that paint widen or narrow the columns, the cells already painted move,
// and that is a layout shift (the fixture site's /issues.html CLS 0.00503 and
// /settings.html CLS 0.0392 on hosted Macs). Every page's head blocks rendering
// until the parser reaches its footer, the one element with id page-end, after
// the main content, so the first paint shows every table whole.
func TestEveryPageWaitsForItsEndBeforeTheFirstPaint(t *testing.T) {
	for _, data := range []Data{calculated(), acmeTable()} {
		for _, name := range PageNames() {
			checkWaitsForItsEnd(t, name, rendered(t, name, data))
		}
	}
}

// checkWaitsForItsEnd holds one rendered page to the head's blocking link and
// to the one footer that ends the wait.
func checkWaitsForItsEnd(t *testing.T, name, html string) {
	t.Helper()
	head, body, found := strings.Cut(html, "</head>")
	if !found {
		t.Fatalf("%s: no </head>", name)
	}
	link := `<link rel="expect" href="#` + pageEnd + `" blocking="render">`
	if !strings.Contains(head, link) {
		t.Errorf("%s: want %s in the head, so no paint shows a table half parsed", name, link)
	}
	checkFooterEndsTheWait(t, name, html, body)
}

// checkFooterEndsTheWait holds a page to exactly one element with the id, the
// footer right after </main>.
func checkFooterEndsTheWait(t *testing.T, name, html, body string) {
	t.Helper()
	id := `id="` + pageEnd + `"`
	if got := strings.Count(html, id); got != 1 {
		t.Errorf("%s: want one element with %s, got %d", name, id, got)
		return
	}
	_, afterMain, found := strings.Cut(body, "</main>")
	if !found || !strings.HasPrefix(strings.TrimSpace(afterMain), `<footer `+id+`>`) {
		t.Errorf("%s: want the footer, right after </main>, to carry %s, so the wait ends after the main content", name, id)
	}
}
