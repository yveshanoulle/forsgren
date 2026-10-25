package needs

import (
	"slices"
	"strings"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// The items of the pull request and push reads GitHub refused (forsgren#321,
// step 2, and forsgren#414): what collect saw in data/pulls_denied.csv and
// data/pushes_denied.csv, so an observed refusal, not a claim about what works
// (decision #314: the setup issue cannot see a fine-grained token's
// permissions in advance). An item names the token that was refused, never its
// value, and the fix that token needs. There is no mark: every run builds the
// items from the file, so an item goes away when a later read of the
// repository cleared its line.

const (
	// jobVariable is the workflow job's token, whose permissions the job sets.
	jobVariable = "GITHUB_TOKEN"
	// fineGrainedVariable is the token a refusal names unless it is the job's.
	fineGrainedVariable = "FORSGREN_TOKEN"
)

// deniedRead is one of the reads whose refusal the setup issue lists: how an
// item names it and what fixes it. The items are not declared in needs.yml.
type deniedRead struct {
	kind       string // the Need kind
	noun       string // "pull request": the read, as an item names it
	objects    string // "the pull requests": what a run that reads it again reads
	permission string // the repository permission of a fine-grained token
	jobFix     string // the fix of the job's token
}

var (
	pullsRead = deniedRead{"pulls_denied", "pull request", "the pull requests",
		"Pull requests: Read", jobFix("pull-requests")}
	pushesRead = deniedRead{"pushes_denied", "push", "the pushes", "Contents: Read", jobFix("contents")}
)

// jobFix is the fix of the job's token for the permission named scope.
func jobFix(scope string) string {
	return "add `" + scope + ": read` to the `permissions:` of the forsgren job in .github/workflows/forsgren.yml."
}

// Refused is the setup issue's items for the pull request reads GitHub
// refused, one per repository of denied, sorted by repository.
func Refused(denied history.Denied) []Need { return pullsRead.items(denied) }

// RefusedPushes is the setup issue's items for the push reads GitHub refused,
// one per repository of denied, sorted by repository.
func RefusedPushes(denied history.Denied) []Need { return pushesRead.items(denied) }

// items are the items of the refusals in denied, sorted by repository.
func (k deniedRead) items(denied history.Denied) []Need {
	repositories := make([]string, 0, len(denied))
	for repository := range denied {
		repositories = append(repositories, repository)
	}
	slices.Sort(repositories)
	items := make([]Need, 0, len(repositories))
	for _, repository := range repositories {
		items = append(items, Need{Kind: k.kind, Steps: k.steps(repository, denied[repository].Token)})
	}
	return items
}

// steps is the item for repository, whose read was refused with the token
// named token, empty for a line of the v1 format.
func (k deniedRead) steps(repository, token string) string {
	permission := "the repository permission " + k.permission + " for " + repository
	var fix string
	switch token {
	case "":
		fix = "; the file that notes it does not name the token. If the token is " + fineGrainedVariable +
			", give it " + permission + "; if it is the job's token, " + k.jobFix
	case jobVariable:
		fix = " with " + jobVariable + ", the job's token. " + strings.ToUpper(k.jobFix[:1]) + k.jobFix[1:]
	default:
		fix = " with " + token + ". Give " + token + " " + permission + "."
	}
	return "forsgren was refused the " + k.noun + " read of " + repository + fix +
		" This item shows a refusal collect saw; it goes away when a run reads " + k.objects + " of " + repository + "."
}
