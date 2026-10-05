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
	var best Published
	found := false
	for _, p := range releases {
		if p.within(installed, level) && beats(best, found, p) {
			best, found = p, true
		}
	}
	return best, found
}

// within says whether p is a published release version that is newer than
// the installed version and no further than level allows. A draft, a
// prerelease, a tag or an installed version that is no release version, and
// an unknown level, are not.
func (p Published) within(installed string, level string) bool {
	if !p.installable() || !release.MatchString(installed) {
		return false
	}
	m := move{from: pin{version: installed}, to: pin{version: p.Tag}}
	_, newer := m.change()
	return newer && m.beyond(level) == ""
}

// installable says whether p is a published release: no draft, no
// prerelease, and a tag that is a release version.
func (p Published) installable() bool {
	return !p.unreleasable() && release.MatchString(p.Tag)
}

// unreleasable says whether p is a draft or a prerelease.
func (p Published) unreleasable() bool {
	return p.Draft || p.Prerelease
}

// beats says whether p is newer than best, or whether there is no best yet:
// found says whether best is one.
func beats(best Published, found bool, p Published) bool {
	return !found || newerThan(best, p)
}

// newerThan says whether the release version of p is newer than that of o.
func newerThan(o, p Published) bool {
	_, newer := move{from: pin{version: o.Tag}, to: pin{version: p.Tag}}.change()
	return newer
}
