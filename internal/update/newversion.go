package update

import "slices"

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

// MovesPinTo says whether a changed file of a pull request moves the pin of
// workflow to version (without the v), so the waiting pull request is found by
// what it changes (forsgren#42).
func MovesPinTo(files []File, workflow, version string) bool {
	return slices.ContainsFunc(files, func(f File) bool {
		return readChanges(f.Patch).movesPinTo(workflow, "v"+version)
	})
}

// movesPinTo says whether c removes one pin line of workflow and adds one, of
// the same workflow, whose version comment is version.
func (c changes) movesPinTo(workflow, version string) bool {
	if c.nRemoved != 1 || c.nAdded != 1 {
		return false
	}
	return c.removed.workflow == workflow && c.added.workflow == workflow && c.added.version == version
}
