package needs

// Marker is the hidden, machine-owned first line of the setup issue's body:
// an HTML comment, invisible on GitHub, by which forsgren finds its one setup
// issue. The title and the rest of the body are presentation only.
const Marker = "<!-- forsgren:setup-issue -->"

// Title is the setup issue's title for a forsgren version.
func Title(version string) string {
	return ""
}

// Body is the setup issue's body: the Marker, a line naming the forsgren
// version that needs the items, then one item per missing need carrying its
// Steps text.
func Body(version string, missing []Need) string {
	return ""
}
