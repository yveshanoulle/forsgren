package page

import (
	"regexp"
	"slices"
	"strconv"
	"strings"
)

// releaseVersion matches a release's version, "0.0.10" or "v0.0.10": three
// numbers, nothing else (a prerelease suffix is not one).
var releaseVersion = regexp.MustCompile(`^v?(\d+)\.(\d+)\.(\d+)$`)

// ReleaseVersion is the version a release tag or version names, without its
// leading "v", and false for anything that is not three dot-separated
// numbers.
func ReleaseVersion(s string) (string, bool) {
	if !releaseVersion.MatchString(s) {
		return "", false
	}
	return strings.TrimPrefix(s, "v"), true
}

// numbers is the three numbers of a version, and false when s is not one
// (or a number does not fit an int).
func numbers(s string) ([3]int, bool) {
	var n [3]int
	found := releaseVersion.FindStringSubmatch(s)
	if found == nil {
		return n, false
	}
	for i := range n {
		v, err := strconv.Atoi(found[i+1])
		if err != nil {
			return n, false
		}
		n[i] = v
	}
	return n, true
}

// newer says whether the release latest is newer than current, comparing
// their numbers as numbers (0.0.10 is newer than 0.0.9), with or without a
// leading "v". What is not a version is never newer.
func newer(current, latest string) bool {
	have, okHave := numbers(current)
	want, okWant := numbers(latest)
	return okHave && okWant && slices.Compare(want[:], have[:]) > 0
}

// Update is the version of a newer forsgren release than Version, which the
// footer names (forsgren#40); empty when Latest is unknown, not a version,
// or not newer.
func (d Data) Update() string {
	if !newer(d.Version, d.Latest) {
		return ""
	}
	version, _ := ReleaseVersion(d.Latest)
	return version
}

// NeedsMore reports whether the check of what this version needs could not
// settle it (forsgren#73): no access, a rate limit or a failure, so the
// footer sends the reader to the run's job summary. ok and empty say nothing.
func (d Data) NeedsMore() bool {
	switch d.NeedsCheck {
	case "no-access", "rate-limited", "failed":
		return true
	}
	return false
}
