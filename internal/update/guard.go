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

// workflowFile is the only file a mergeable pull request changes: the data
// repository's workflow that holds the pin.
const workflowFile = ".github/workflows/forsgren.yml"

// manyPins is the reason of a patch with more than one removed or added pin
// line.
const manyPins = "more than one pin line changed"

// Decide says whether p may be merged: only when it changes the workflow file
// alone, by one removed and one added pin line and nothing else. Otherwise
// the reason names what else changed. It reports the old and new version and
// the new sha it saw.
func Decide(p Pull) Decision {
	var patches []string
	for _, f := range p.Files {
		if f.Filename != workflowFile {
			return Decision{Reason: "changed besides the pin line: " + f.Filename}
		}
		patches = append(patches, f.Patch)
	}
	c := readChanges(strings.Join(patches, "\n"))
	if reason := c.reason(); reason != "" {
		return Decision{Reason: reason}
	}
	if len(c.removed) == 0 || len(c.added) == 0 {
		return Decision{Reason: "no pin line changed"}
	}
	return Decision{Merge: true, Old: c.removed[0][3], New: c.added[0][3], NewSHA: c.added[0][2]}
}

// changes are the changed lines of a patch: the matches of its removed and
// of its added pin lines, and the changed lines that are no pin line.
type changes struct {
	removed [][]string
	added   [][]string
	others  []string
}

// readChanges sorts the lines of a patch into changes. GitHub's patch text
// starts at the first hunk header and has no file headers, so a changed line
// is one that starts with + or -.
func readChanges(patch string) changes {
	var c changes
	for _, line := range strings.Split(patch, "\n") {
		c.add(line)
	}
	return c
}

// add sorts one patch line into c; a context line or a hunk header is none.
func (c *changes) add(line string) {
	m := pinLine.FindStringSubmatch(line)
	switch {
	case m == nil:
		if strings.HasPrefix(line, "+") || strings.HasPrefix(line, "-") {
			c.others = append(c.others, line)
		}
	case m[1] == "-":
		c.removed = append(c.removed, m)
	default:
		c.added = append(c.added, m)
	}
}

// reason is the reason line a human reads: a second pin line of either kind,
// or the changed lines that are no pin line, quoted; empty when there is
// neither.
func (c changes) reason() string {
	if len(c.removed) > 1 || len(c.added) > 1 {
		return manyPins
	}
	if len(c.others) > 0 {
		return "changed besides the pin line: " + strings.Join(c.others, "; ")
	}
	return ""
}
