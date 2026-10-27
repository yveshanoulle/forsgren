package collect

// The service of a failure issue (forsgren#515, step 2): the `service:` line
// of its record block names a row of the issue's repository as the page shows
// it, a service's label or a deployment rule's label, matched ignoring case
// (decision #516 A). The label is stored as the config spells it. One that
// matches no row, or more than one, is stored empty, so the failure counts in
// the total only, and is named on stderr and in the report, never guessed and
// never a failure of the run (decision #517 A).

import (
	"maps"
	"slices"
	"strings"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/github"
)

// repositoriesOf are the repositories of cfg by lower-case name.
func repositoriesOf(cfg config.Config) map[string]config.Repository {
	out := map[string]config.Repository{}
	for _, p := range cfg.Projects {
		for _, r := range p.Repositories {
			out[strings.ToLower(r.Name)] = r
		}
	}
	return out
}

// rowLabels are the labels of the service and rule rows of repo.
func rowLabels(repo config.Repository) []string {
	labels := slices.Collect(maps.Values(repo.Services))
	for _, rule := range repo.Rules {
		if rule.Label != "" {
			labels = append(labels, rule.Label)
		}
	}
	return labels
}

// resolveService is the label of the one row of repo that label names,
// ignoring case, spelled as the config spells it; when it names none, or
// more than one, the reason is ServiceUnknown or ServiceAmbiguous.
func resolveService(repo config.Repository, label string) (service, reason string) {
	var found []string
	for _, l := range rowLabels(repo) {
		if label != "" && strings.EqualFold(l, label) {
			found = append(found, l)
		}
	}
	switch len(found) {
	case 0:
		return "", ServiceUnknown
	case 1:
		return found[0], ""
	}
	return "", ServiceAmbiguous
}

// serviceOf is the service to store for issue i of repo: the row its record's
// service line names, empty without a line, and empty with a report and a
// line on stderr when the line names no single row.
func (o Options) serviceOf(repo string, i github.Issue) string {
	label := i.Record.Service
	if label == "" {
		return ""
	}
	service, reason := resolveService(o.repositories[strings.ToLower(repo)], label)
	if reason == "" {
		return service
	}
	words := "is unknown in this repository"
	if reason == ServiceAmbiguous {
		words = "is ambiguous in this repository (it matches more than one row)"
	}
	o.warn("collect: %s: failure issue #%d: service %q %s; the failure was counted in the total only\n",
		repo, i.Number, label, words)
	if o.Report != nil {
		o.Report.ServiceUnmatched = append(o.Report.ServiceUnmatched,
			UnmatchedService{Repository: repo, Issue: i.Number, Reason: reason, Label: label})
	}
	return ""
}
