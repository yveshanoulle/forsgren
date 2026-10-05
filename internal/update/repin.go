package update

import (
	"fmt"
	"regexp"
	"strings"
)

// Target is the pin a caller file is moved to: the workflow file of forsgren
// it calls, and the release version and commit it pins.
type Target struct {
	Workflow string
	Version  string
	SHA      string
}

// Repin moves the one pin line of forsgren's workflow to.Workflow in content,
// a caller file, to to.SHA and to.Version, keeping the indentation and what
// follows the version comment. A file with no such line or with more than
// one is an error naming the workflow.
func Repin(content string, to Target) (string, error) {
	line := pinFileLine(to.Workflow)
	if n := len(line.FindAllStringIndex(content, -1)); n != 1 {
		return "", fmt.Errorf("want one pin line of %s, found %d", to.Workflow, n)
	}
	return line.ReplaceAllString(content, "${1}"+literal(to.SHA)+"${2}"+literal(to.Version)), nil
}

// pinFileLine matches the pin line of workflow in a caller file, as pinLine
// does in a patch, without its sign: the indentation, the uses key and the
// workflow up to the at sign (group 1), the 40-hex sha, the comment marker
// (group 2) and the release version.
func pinFileLine(workflow string) *regexp.Regexp {
	return regexp.MustCompile(`(?m)^([ \t]*(?:- )?uses: yveshanoulle/forsgren/\.github/workflows/` +
		regexp.QuoteMeta(workflow) + `@)[0-9a-f]{40}( # )v\d+\.\d+\.\d+`)
}

// literal is s as a regexp replacement template takes it literally.
func literal(s string) string { return strings.ReplaceAll(s, "$", "$$") }
