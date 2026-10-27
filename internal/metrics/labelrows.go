package metrics

// The walk over a project's labels that the TBD table and the Week table
// share (forsgren#531, step 1): each labelled repository as a project of its
// own, each labelled service and rule over its own data and paths, sorted by
// label ignoring case.

import (
	"slices"
	"strings"

	"github.com/yveshanoulle/forsgren/internal/config"
)

// labelBuilders make a row of type R: of a repository (a project of one) and
// of a service or rule, with the project's name, its own data and its paths.
type labelBuilders[R any] struct {
	repository func(only config.Project, project string) R
	service    func(only config.Project, project string, own Data, paths []string) R
	name       func(R) string
}

// labelledRows are the rows of p's labels over data, sorted by name ignoring
// case.
func labelledRows[R any](p config.Project, data Data, b labelBuilders[R]) []R {
	var rows []R
	for _, r := range p.Repositories {
		labelled := config.Project{Name: r.Label, Repositories: []config.Repository{r}}
		if r.Label != "" {
			rows = append(rows, b.repository(labelled, p.Name))
		}
		for task, label := range r.Services {
			labelled.Name = label
			rows = append(rows, b.service(labelled, p.Name, data.ofTask(r.Name, task), r.Paths[task]))
		}
		for _, rule := range r.Rules {
			labelled.Name = rule.Label
			rows = append(rows, b.service(labelled, p.Name, data.ofRule(r.Name, rule.Deployment), rule.Paths))
		}
	}
	slices.SortFunc(rows, func(a, c R) int {
		return strings.Compare(strings.ToLower(b.name(a)), strings.ToLower(b.name(c)))
	})
	return rows
}
