// Package update is the guard of forsgren#58: pure decisions on whether
// Dependabot's pull request in an installation's data repository may be
// merged. It reads no network; the caller hands it what GitHub answered.
package update

// File is one changed file of a pull request as GitHub's GET
// /repos/{owner}/{repo}/pulls/{number}/files returns it: the path and the
// unified patch text.
type File struct {
	Filename string
	Patch    string
}

// Pull is everything the guard looks at. Later steps add fields (the level,
// the published releases), never a second shape.
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

// Decide says whether p may be merged. Step 58-8 scaffold: it always leaves
// the pull request for a human.
func Decide(p Pull) Decision {
	return Decision{Reason: "not decided yet"}
}
