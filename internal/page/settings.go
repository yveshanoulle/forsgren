package page

// The settings page's Possible values column (forsgren#141): what each optional
// key of forsgren.config.yml accepts, as the page shows it.

// possibleValues are the values each key accepts, by key name.
var possibleValues = map[string]string{
	"view":               "standard, numbers, scoring",
	"auto_update":        "true, false",
	"auto_update_level":  "patch, minor, major",
	"history_days":       "1 to 1825",
	"history_chunk_days": "1 to 365",
	"working_hours":      "1 to 24",
}

// possibleOf is the values the key accepts, empty for a key the page does not
// know.
func possibleOf(key string) string { return possibleValues[key] }
