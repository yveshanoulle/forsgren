// Package update is the guard of forsgren#58: pure decisions on whether
// Dependabot's pull request in an installation's data repository may be
// merged. It reads no network; the caller hands it what GitHub answered.
package update

import (
	"fmt"
	"regexp"
	"strings"

	"github.com/yveshanoulle/forsgren/internal/config"
)

// File is one changed file of a pull request as GitHub's GET
// /repos/{owner}/{repo}/pulls/{number}/files returns it: the path and the
// unified patch text.
type File struct {
	Filename string
	Patch    string
}

// Release is what the caller looked up for the new version of the pins, so
// that the guard reads no network: whether GitHub has a published release of
// forsgren for it (GET /repos/yveshanoulle/forsgren/releases/tags/{tag}) and
// the commit its tag points at.
type Release struct {
	Published bool
	SHA       string
}

// Pull is everything the guard looks at: the author, the changed files, the
// release of the new version and the installation's auto_update_level, one of
// the config package's LevelPatch, LevelMinor and LevelMajor, how far an
// update may go before it merges itself.
type Pull struct {
	Author  string
	Files   []File
	Release Release
	Level   string
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

// release is a release version of forsgren: v and three numbers, no
// pre-release or build suffix.
var release = regexp.MustCompile(`^v(\d+)\.(\d+)\.(\d+)$`)

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

// dependabot is the login of the only author whose pull request may be
// merged, spelled exactly so.
const dependabot = "dependabot[bot]"

// Decide says whether p may be merged: only when its author is dependabot[bot]
// and every changed file is a caller, changed by one removed and one added pin
// line of its workflow and nothing else, and all pins move from the same
// version to the same version and sha, as Dependabot moves them in one pull
// request, by no more than p.Level allows, to a published release of forsgren
// whose tag points at the pinned sha. Otherwise the reason names the author or
// what else changed. It reports the old and new version and the new sha it
// saw.
func Decide(p Pull) Decision {
	if p.Author != dependabot {
		return Decision{Reason: fmt.Sprintf("the author is %q, not %s", p.Author, dependabot)}
	}
	if len(p.Files) == 0 {
		return Decision{Reason: noPin}
	}
	first, reason := readCallers(p.Files)
	if reason != "" {
		return Decision{Reason: reason}
	}
	if reason := first.beyond(p.Level); reason != "" {
		return Decision{Reason: reason}
	}
	if reason := p.Release.refuses(first.to); reason != "" {
		return Decision{Reason: reason}
	}
	return Decision{Merge: true, Old: first.from.version, New: first.to.version, NewSHA: first.to.sha}
}

// refuses is the reason a pin to to is no pin to this release: the version
// has no published release of forsgren, or its tag points at another commit
// than the pinned one; empty when it is.
func (r Release) refuses(to pin) string {
	if !r.Published {
		return to.version + " is no published release of forsgren"
	}
	if r.SHA != to.sha {
		return fmt.Sprintf("the tag %s points at %s, not at the pinned %s", to.version, r.SHA, to.sha)
	}
	return ""
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
// workflow other than the one it calls, or has versions that are no upgrade
// between two releases.
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
	return m, m.unfit(f.Filename)
}

// unfit is the reason the versions of m are not those of an upgrade between
// two releases: one is no release version, or the new one is not newer than
// the old one. The versions are judged before the release lookup, which only
// speaks for a version that is a release version and an upgrade. Empty when
// they are.
func (m move) unfit(filename string) string {
	if v := m.unreleased(); v != "" {
		return fmt.Sprintf("changed besides the pin line: %s pins %q, which is no release version", filename, v)
	}
	if _, newer := m.change(); !newer {
		return m.String() + " is no upgrade"
	}
	return ""
}

// kinds name the parts of a release version, major first, as the kind of an
// update that first differs in that part.
var kinds = [...]string{"major", "minor", "patch"}

// levels give, for each auto_update_level, the first part of a version that
// an update may change: patch only the patch number, minor the minor or the
// patch number, major any.
var levels = map[string]int{
	config.LevelPatch: 2,
	config.LevelMinor: 1,
	config.LevelMajor: 0,
}

// change finds the first part, 0 major, 1 minor, 2 patch, in which the
// versions of m differ, and says whether the new one is newer there, the
// parts compared as numbers: v0.1.10 is newer than v0.1.9. Equal versions
// differ in no part, which is len(kinds), and are not newer. Both versions
// must be release versions.
func (m move) change() (int, bool) {
	from := release.FindStringSubmatch(m.from.version)[1:]
	to := release.FindStringSubmatch(m.to.version)[1:]
	for i := range from {
		if from[i] != to[i] {
			return i, smaller(from[i], to[i])
		}
	}
	return len(kinds), false
}

// beyond is the reason the update of m goes further than level allows, naming
// the kind of update and the level; or that there is no known level. Empty
// when the update is within the level. m must be an upgrade.
func (m move) beyond(level string) string {
	allowed, ok := levels[level]
	if !ok {
		return "no auto_update_level set"
	}
	if part, _ := m.change(); part < allowed {
		return fmt.Sprintf("%s is a %s update; auto_update_level is %s", m, kinds[part], level)
	}
	return ""
}

// smaller says whether the number a is below the number b, both written as
// digits: after leading zeros, the shorter is smaller, and of equal length
// the one that sorts first.
func smaller(a, b string) bool {
	a, b = strings.TrimLeft(a, "0"), strings.TrimLeft(b, "0")
	if len(a) != len(b) {
		return len(a) < len(b)
	}
	return a < b
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

// unreleased is the first version of m, the removed pin's before the added
// one's, that is no release version; empty when both are.
func (m move) unreleased() string {
	for _, v := range []string{m.from.version, m.to.version} {
		if !release.MatchString(v) {
			return v
		}
	}
	return ""
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
