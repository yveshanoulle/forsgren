package update

// NewVersion is the version the added pin line of the first changed file that
// has one moves to, for the caller to look up its release before it calls
// Decide; false when no file adds a pin line.
func NewVersion(files []File) (string, bool) {
	for _, f := range files {
		if c := readChanges(f.Patch); c.nAdded > 0 {
			return c.added.version, true
		}
	}
	return "", false
}
