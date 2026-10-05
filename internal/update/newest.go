package update

// Published is one release of forsgren as GitHub lists it: the tag, the
// commit the tag points at, and whether it is a draft or a prerelease.
type Published struct {
	Tag        string
	SHA        string
	Draft      bool
	Prerelease bool
}

// NewestWithin picks the newest of releases that is newer than the installed
// version and within level, as beyond() reads it. Drafts, prereleases and
// tags that are no release version are skipped. It reports false when there
// is none.
func NewestWithin(installed string, level string, releases []Published) (Published, bool) {
	return Published{}, false
}
