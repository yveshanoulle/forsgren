package needs

import (
	"regexp"
	"strings"
	"time"
)

// Marker is the hidden, machine-owned first line of the setup issue's body:
// an HTML comment, invisible on GitHub, by which forsgren finds its one setup
// issue. The title and the rest of the body are presentation only.
const Marker = "<!-- forsgren:setup-issue -->"

// Title is the setup issue's title for a forsgren version.
func Title(version string) string {
	return "forsgren " + version + " needs more configuration"
}

// Body is the setup issue's body: the Marker as its first line, a sentence
// naming the forsgren version that needs the items, then one task-list item
// per missing need carrying its Steps text.
func Body(version string, missing []Need) string {
	var b strings.Builder
	b.WriteString(Marker)
	b.WriteString("\n\nforsgren " + version + " needs more configuration in this repository. ")
	b.WriteString("Each item below is missing; forsgren closes this issue once all are in place.\n")
	for _, n := range missing {
		b.WriteString("\n- [ ] " + n.Steps)
		if n.Hidden != "" {
			b.WriteString(" " + n.Hidden)
		}
	}
	b.WriteString("\n")
	return b.String()
}

// tokenExpiryMarkPattern finds the token expiry mark in a setup issue's body.
var tokenExpiryMarkPattern = regexp.MustCompile(`<!-- forsgren:token_expiry (\S+) -->`)

// TokenExpiryMark is the hidden HTML comment the token renewal item carries
// in the setup issue's body, naming the expiry date it was written for
// (forsgren#177): the issue says by it, not by its prose, that it carries the
// item, and with which date.
func TokenExpiryMark(expiry time.Time) string {
	return "<!-- forsgren:token_expiry " + expiry.UTC().Format(time.RFC3339) + " -->"
}

// TokenExpiryIn is the expiry date the first token expiry mark in body
// names, and whether body has one that names a date.
func TokenExpiryIn(body string) (time.Time, bool) {
	m := tokenExpiryMarkPattern.FindStringSubmatch(body)
	if m == nil {
		return time.Time{}, false
	}
	expiry, err := time.Parse(time.RFC3339, m[1])
	return expiry, err == nil
}
