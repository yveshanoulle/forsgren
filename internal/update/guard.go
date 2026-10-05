// Package update is the guard of forsgren#58: pure decisions on whether
// Dependabot's pull request in an installation's data repository may be
// merged. It reads no network; the caller hands it what GitHub answered.
package update

import (
	"fmt"
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
	`^([-+])\s*uses: yveshanoulle/forsgren/\.github/workflows/([^@\s]+)@([0-9a-f]{40}) # (\S+)$`)

// callers are the files of an installation's data repository that pin
// forsgren, each with the one workflow of forsgren it calls: forsgren.yml
// calls metrics.yml and forsgren-update.yml calls auto_update.yml.
var callers = map[string]string{
	".github/workflows/forsgren.yml":        "metrics.yml",
	".github/workflows/forsgren-update.yml": "auto_update.yml",
}

// manyPins is the reason of a patch with more than one removed or added pin
// line.
const manyPins = "more than one pin line changed"

// noPin is the reason of a pull request that changes no file.
const noPin = "no pin line changed"

// Decide says whether p may be merged: only when every changed file is a
// caller, changed by one removed and one added pin line of its workflow and
// nothing else, and all pins move from the same version to the same version
// and sha, as Dependabot moves them in one pull request. Otherwise the reason
// names what else changed. It reports the old and new version and the new
// sha it saw.
func Decide(p Pull) Decision {
	if len(p.Files) == 0 {
		return Decision{Reason: noPin}
	}
	first, reason := readCallers(p.Files)
	if reason != "" {
		return Decision{Reason: reason}
	}
	return Decision{Merge: true, Old: first.from.version, New: first.to.version, NewSHA: first.to.sha}
}

// readCallers reads the pin pair of every changed file and returns the first
// one. The reason is not empty when a file is not mergeable (readCaller) or
// its pins move differently from the first file's.
func readCallers(files []File) (move, string) {
	var first move
	for i, f := range files {
		m, reason := readCaller(f)
		if reason != "" {
			return m, reason
		}
		if i == 0 {
			first = m
		} else if !m.agrees(first) {
			return m, "the pins move differently: " + first.String() + " and " + m.String()
		}
	}
	return first, ""
}

// readCaller reads the pin pair of one changed file. The reason is not empty
// when the file is no caller, changes more than its pin pair, or pins a
// workflow other than the one it calls.
func readCaller(f File) (move, string) {
	want, ok := callers[f.Filename]
	if !ok {
		return move{}, "changed besides the pin line: " + f.Filename
	}
	c := readChanges(f.Patch)
	if reason := c.reason(); reason != "" {
		return move{}, reason
	}
	m := move{from: c.removed, to: c.added}
	if m.from.workflow != want || m.to.workflow != want {
		return m, fmt.Sprintf("changed besides the pin line: %s moves %q to %q, want %q",
			f.Filename, m.from.workflow, m.to.workflow, want)
	}
	return m, ""
}

// pin is one pin line: the workflow file of forsgren, the commit and the
// version comment.
type pin struct {
	workflow string
	sha      string
	version  string
}

// move is a pin line removed and the one added in its place.
type move struct {
	from pin
	to   pin
}

// String names the versions of m, for a reason line.
func (m move) String() string {
	return m.from.version + " to " + m.to.version
}

// agrees says whether m leaves the same version for the same version and sha
// as o; the workflow files differ between callers.
func (m move) agrees(o move) bool {
	return m.from.version == o.from.version && m.to.version == o.to.version && m.to.sha == o.to.sha
}

// changes are the changed lines of a patch: the count of its removed and of
// its added pin lines, the last of each (empty when there is none), and the
// changed lines that are no pin line.
type changes struct {
	removed  pin
	added    pin
	nRemoved int
	nAdded   int
	others   []string
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
		c.removed, c.nRemoved = pin{workflow: m[2], sha: m[3], version: m[4]}, c.nRemoved+1
	default:
		c.added, c.nAdded = pin{workflow: m[2], sha: m[3], version: m[4]}, c.nAdded+1
	}
}

// reason is the reason line a human reads: a second pin line of either kind,
// or the changed lines that are no pin line, quoted; empty when there is
// neither.
func (c changes) reason() string {
	if c.nRemoved > 1 || c.nAdded > 1 {
		return manyPins
	}
	if len(c.others) > 0 {
		return "changed besides the pin line: " + strings.Join(c.others, "; ")
	}
	return ""
}
