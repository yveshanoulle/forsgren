// Package update is the guard of forsgren#58: pure decisions on whether
// Dependabot's pull request in an installation's data repository may be
// merged. It reads no network; the caller hands it what GitHub answered.
package update

import (
	"regexp"
	"strings"
)

// File is one changed file of a pull request as GitHub's GET
// /repos/{owner}/{repo}/pulls/{number}/files returns it: the path and the
// unified patch text.
type File struct {
	Filename string
	Patch    string
}

// Pull is everything the guard looks at: the author and the changed files.
type Pull struct {
	Author string
	Files  []File
}

// Decision is the guard's answer: Merge, or left for a human with one
// Reason line. Old, New and NewSHA are the pin the guard saw, empty when it
// saw none.
type Decision struct {
	Merge  bool
	Reason string
	Old    string
	New    string
	NewSHA string
}

// pinLine is a pin of forsgren's reusable workflow as a diff line shows it:
// the sign, the uses key, the workflow file, a 40-hex sha and the version
// comment (forsgren.yml of an installation, README, Running forsgren).
var pinLine = regexp.MustCompile(
	`^([-+])\s*uses: yveshanoulle/forsgren/\.github/workflows/[^@\s]+@([0-9a-f]{40}) # (\S+)$`)

// Decide says whether p may be merged: only when a pin line was removed and
// one added. It reports the old and new version and the new sha it saw.
func Decide(p Pull) Decision {
	var d Decision
	for _, f := range p.Files {
		d = readPins(f.Patch, d)
	}
	d.Merge = d.Old != "" && d.New != ""
	return d
}

// readPins adds the removed and the added pin line of a patch to d: the
// version of the removed one as Old, the version and sha of the added one.
func readPins(patch string, d Decision) Decision {
	for _, line := range strings.Split(patch, "\n") {
		m := pinLine.FindStringSubmatch(line)
		if m == nil {
			continue
		}
		if m[1] == "-" {
			d.Old = m[3]
		} else {
			d.New, d.NewSHA = m[3], m[2]
		}
	}
	return d
}
