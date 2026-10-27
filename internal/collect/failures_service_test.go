package collect

import (
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// serviceBody is a failure issue body with a record block and a service line.
func serviceBody(service string) string {
	return `"Checkout crashes.\r\n\r\nfailure-start: 2026-09-20T09:12+02:00\r\nservice: ` + service + `\r\n"`
}

// withServices is acme/app with the services Web and Admin.
func withServices() config.Repository {
	r := production
	r.Services = map[string]string{"web": "Web", "admin": "Admin"}
	return r
}

// withRuleLabels is acme/app written with `deployments:`, one rule labelled
// Releases.
func withRuleLabels() config.Repository {
	r := production
	r.Rules = []config.Rule{{Deployment: r.Deployment, Label: "Releases"}}
	return r
}

// serviceFailure is the stored issue 42 of acme/app with service.
func serviceFailure(service string) history.Failure {
	f := failure(42, at(20, 8, 0), time.Time{}, at(20, 7, 12))
	f.Service = service
	return f
}

// collectService collects one failure issue 42 whose body has the service
// line service, for repo, and returns the result, the history path and the
// fake.
func collectService(t *testing.T, repo config.Repository, service string) (result, string, *gitHub) {
	t.Helper()
	g := issuesOnly(t, issueJSON(42, "2026-09-20T08:00:00Z", "", serviceBody(service)))
	path := historyPath(t)
	return g.collect(t, shop(repo), path, github.DefaultMaxPages), path, g
}

// wantUnmatched fails unless the run reported exactly want, with no error.
func wantUnmatched(t *testing.T, g *gitHub, r result, want UnmatchedService, stderr string) {
	t.Helper()
	if r.err != nil || r.stderr != stderr {
		t.Errorf("want no error and stderr %q, got %v, %q", stderr, r.err, r.stderr)
	}
	g.wantReportOf(t, Report{ServiceUnmatched: []UnmatchedService{want}})
}

// TestAServiceLabelIsStoredAsTheConfigSpellsIt (forsgren#515, step 2): a
// service label, matched ignoring case, is stored as the config spells it,
// and nothing is said.
func TestAServiceLabelIsStoredAsTheConfigSpellsIt(t *testing.T) {
	r, path, g := collectService(t, withServices(), "wEB")
	wantNoStderr(t, r)
	wantFailures(t, path, serviceFailure("Web"))
	g.wantReportOf(t, Report{})
}

// TestADeploymentRuleLabelIsStoredAsTheConfigSpellsIt: a rule's label is a
// row label as well.
func TestADeploymentRuleLabelIsStoredAsTheConfigSpellsIt(t *testing.T) {
	r, path, _ := collectService(t, withRuleLabels(), "releases")
	wantNoStderr(t, r)
	wantFailures(t, path, serviceFailure("Releases"))
}

// TestAnUnknownServiceLabelCountsInTheTotalOnlyAndIsReported (decision #517):
// stored with an empty service, named on stderr and in the report with the
// repository, the issue and the label, and the run does not fail.
func TestAnUnknownServiceLabelCountsInTheTotalOnlyAndIsReported(t *testing.T) {
	r, path, g := collectService(t, withServices(), "Mobile app")
	wantUnmatched(t, g, r, UnmatchedService{"acme/app", 42, ServiceUnknown, "Mobile app"},
		"collect: acme/app: failure issue #42: service \"Mobile app\" is unknown in this repository; "+
			"the failure was counted in the total only\n")
	wantFailures(t, path, serviceFailure(""))
}

// TestAServiceLabelThatMatchesTwoRowsIsAmbiguousAndNeverGuessed (decision
// #516): two rows with the label, ignoring case, store an empty service.
func TestAServiceLabelThatMatchesTwoRowsIsAmbiguousAndNeverGuessed(t *testing.T) {
	repo := production
	repo.Services = map[string]string{"web": "Web", "site": "WEB"}
	r, path, g := collectService(t, repo, "web")
	wantUnmatched(t, g, r, UnmatchedService{"acme/app", 42, ServiceAmbiguous, "web"},
		"collect: acme/app: failure issue #42: service \"web\" is ambiguous in this repository "+
			"(it matches more than one row); the failure was counted in the total only\n")
	wantFailures(t, path, serviceFailure(""))
}

// TestARepositoryWithoutRowsKnowsNoServiceLabel: any service line is unknown.
func TestARepositoryWithoutRowsKnowsNoServiceLabel(t *testing.T) {
	r, path, g := collectService(t, production, "Web")
	wantUnmatched(t, g, r, UnmatchedService{"acme/app", 42, ServiceUnknown, "Web"},
		"collect: acme/app: failure issue #42: service \"Web\" is unknown in this repository; "+
			"the failure was counted in the total only\n")
	wantFailures(t, path, serviceFailure(""))
}

// TestARecordWithoutAServiceLineStaysAsItWas: no service, nothing said.
func TestARecordWithoutAServiceLineStaysAsItWas(t *testing.T) {
	g := issuesOnly(t, issueJSON(42, "2026-09-20T08:00:00Z", "", recordBlock))
	path := historyPath(t)
	r := g.collect(t, shop(withServices()), path, github.DefaultMaxPages)
	wantNoStderr(t, r)
	wantFailures(t, path, serviceFailure(""))
	g.wantReportOf(t, Report{})
}

// TestAServiceFixedInTheConfigIsStoredAsANewLine: an issue stored with no
// service, read again after the config names its label, gets a new line.
func TestAServiceFixedInTheConfigIsStoredAsANewLine(t *testing.T) {
	g := issuesOnly(t, issueJSON(42, "2026-09-20T08:00:00Z", "", serviceBody("Web")))
	path := historyPath(t)
	g.collect(t, shop(production), path, github.DefaultMaxPages)
	g.collect(t, shop(withServices()), path, github.DefaultMaxPages)
	wantFailures(t, path, serviceFailure("Web"))
}

// TestResolveServiceReadsTheRowsOfTheRepository: services and rules alike,
// ignoring case, the config's spelling back; unknown and ambiguous apart.
func TestResolveServiceReadsTheRowsOfTheRepository(t *testing.T) {
	both := production
	both.Services = map[string]string{"a": "Web"}
	both.Rules = []config.Rule{{Label: "web"}, {Label: "Site"}, {}}
	for name, c := range map[string]struct {
		repo           config.Repository
		label          string
		service, cause string
	}{
		"a service":   {withServices(), "ADMIN", "Admin", ""},
		"a rule":      {withRuleLabels(), "RELEASES", "Releases", ""},
		"a rule only": {both, "site", "Site", ""},
		"both":        {both, "WEB", "", ServiceAmbiguous},
		"unknown":     {withServices(), "Api", "", ServiceUnknown},
		"no rows":     {production, "Web", "", ServiceUnknown},
		"empty label": {both, "", "", ServiceUnknown},
	} {
		t.Run(name, func(t *testing.T) {
			if service, cause := resolveService(c.repo, c.label); service != c.service || cause != c.cause {
				t.Errorf("want %q, %q, got %q, %q", c.service, c.cause, service, cause)
			}
		})
	}
}
