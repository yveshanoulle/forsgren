package update

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
	return "", nil
}
