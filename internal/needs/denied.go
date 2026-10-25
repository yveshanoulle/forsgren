package needs

import (
	"slices"
	"strings"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// The items of the pull request reads GitHub refused (forsgren#321, step 2):
// what collect saw in data/pulls_denied.csv, so an observed refusal, not a
// claim about what works (decision #314: the setup issue cannot see a
// fine-grained token's permissions in advance). An item names the token that
// was refused, never its value, and the fix that token needs. There is no
// mark: every run builds the items from the file, so an item goes away when a
// later read of the repository cleared its line.

const (
	// jobVariable is the workflow job's token, whose permissions the job sets.
	jobVariable = "GITHUB_TOKEN"
	// fineGrainedVariable is the token a refusal names unless it is the job's.
	fineGrainedVariable = "FORSGREN_TOKEN"
	// deniedKind is the kind of these items; they are not declared in needs.yml.
	deniedKind = "pulls_denied"
	jobFix     = "add `pull-requests: read` to the `permissions:` of the forsgren job in " +
		".github/workflows/forsgren.yml."
)

// Refused is the setup issue's items for the pull request reads GitHub
// refused, one per repository of denied, sorted by repository.
func Refused(denied history.PullsDenied) []Need {
	repositories := make([]string, 0, len(denied))
	for repository := range denied {
		repositories = append(repositories, repository)
	}
	slices.Sort(repositories)
	items := make([]Need, 0, len(repositories))
	for _, repository := range repositories {
		items = append(items, Need{Kind: deniedKind, Steps: refusedSteps(repository, denied[repository].Token)})
	}
	return items
}

// refusedSteps is the item for repository, whose read was refused with the
// token named token, empty for a line of the pulls denied format v1.
func refusedSteps(repository, token string) string {
	permission := "the repository permission Pull requests: Read for " + repository
	var fix string
	switch token {
	case "":
		fix = "; the file that notes it does not name the token. If the token is " + fineGrainedVariable +
			", give it " + permission + "; if it is the job's token, " + jobFix
	case jobVariable:
		fix = " with " + jobVariable + ", the job's token. " + strings.ToUpper(jobFix[:1]) + jobFix[1:]
	default:
		fix = " with " + token + ". Give " + token + " " + permission + "."
	}
	return "forsgren was refused the pull request read of " + repository + fix +
		" This item shows a refusal collect saw; it goes away when a run reads the pull requests of " + repository + "."
}
