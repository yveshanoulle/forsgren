package needs

import "strings"

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
	}
	b.WriteString("\n")
	return b.String()
}
