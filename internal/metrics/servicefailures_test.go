package metrics

import (
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// The failure issues of a service or a deployment rule (forsgren#515, step
// 3): a row counts the failures whose stored Service is its label, over its
// own deployments; the total row counts every failure of the project, with a
// service or without.

// serviceProjects is one project whose repository acme/app has two services.
var serviceProjects = []config.Project{{Name: "Acme App", Repositories: []config.Repository{{
	Name: "acme/app", Services: map[string]string{"deploy-api": "API", "deploy-admin": "ADMIN"},
}}}}

// serviceData: API has two successes, ADMIN one, an hour and two days ago. The
// failure issue 1 is API's and open since yesterday, 2 is ADMIN's and was
// closed four days ago, 3 names no service and is open since yesterday.
func serviceData() Data {
	ok := history.StateSuccess
	return Data{
		Records: []history.Record{
			appDeployment(1, "deploy-api", ok, time.Hour),
			appDeployment(2, "deploy-api", ok, 2*day),
			appDeployment(3, "deploy-admin", ok, time.Hour),
		},
		Failures: []history.Failure{
			{Repository: "acme/app", Issue: 1, OpenedAt: now.Add(-day), Service: "API"},
			{Repository: "acme/app", Issue: 2, OpenedAt: now.Add(-5 * day), ClosedAt: now.Add(-4 * day), Service: "ADMIN"},
			{Repository: "acme/app", Issue: 3, OpenedAt: now.Add(-day)},
		},
	}
}

// failFigures are a row's change fail rate counts and its rework counts.
type failFigures struct{ deployments, issues, failed, reworkOf, rework int }

func failFiguresOf(r Row) failFigures {
	c := r.ChangeFail
	return failFigures{c.Deployments, c.FailureIssues, c.Failed, r.Rework.Deployments, r.Rework.Rework}
}

// wantFailFigures fails unless each named row has the figures.
func wantFailFigures(t *testing.T, rows []Row, want map[string]failFigures) {
	t.Helper()
	for name, w := range want {
		if got := failFiguresOf(rowNamed(t, rows, name)); got != w {
			t.Errorf("%s: want %+v, got %+v", name, w, got)
		}
	}
}

// TestAServiceRowCountsTheFailuresNamingItAndTheTotalCountsAll: the total
// counts the three issues, API only issue 1 and ADMIN only issue 2, and the
// issue without a service counts in the total alone. Rework follows: issue 1
// is open when deployment 1 is made, so API's deployment 1 is rework and
// ADMIN's deployment 3 is not, though issue 1 was open then.
func TestAServiceRowCountsTheFailuresNamingItAndTheTotalCountsAll(t *testing.T) {
	rows := Rows(serviceProjects, serviceData(), now)
	wantFailFigures(t, rows, map[string]failFigures{
		"Acme App": {3, 3, 3, 3, 2},
		"API":      {2, 1, 1, 2, 1},
		"ADMIN":    {1, 1, 1, 1, 0},
	})
}

// TestAFailureOfAnotherServiceIsNotInTheRow: with only ADMIN's issue, API
// has none and counts nothing.
func TestAFailureOfAnotherServiceIsNotInTheRow(t *testing.T) {
	data := serviceData()
	data.Failures = data.Failures[1:2]
	rows := Rows(serviceProjects, data, now)
	wantFailFigures(t, rows, map[string]failFigures{
		"Acme App": {3, 1, 1, 3, 0},
		"API":      {2, 0, 0, 2, 0},
		"ADMIN":    {1, 1, 1, 1, 0},
	})
}

// TestAServiceIsMatchedIgnoringCase: a stored label in another case still
// names the row.
func TestAServiceIsMatchedIgnoringCase(t *testing.T) {
	data := serviceData()
	data.Failures[0].Service = "api"
	rows := Rows(serviceProjects, data, now)
	wantFailFigures(t, rows, map[string]failFigures{"API": {2, 1, 1, 2, 1}})
}

// TestARuleRowCountsTheFailuresNamingIt: the rule rows Releases and Site, the
// issue naming Site is in Site and the total, the one naming none in the
// total alone.
func TestARuleRowCountsTheFailuresNamingIt(t *testing.T) {
	data := ruledData()
	data.Failures = []history.Failure{
		{Repository: "acme/site", Issue: 1, OpenedAt: now.Add(-day), Service: "Site"},
		{Repository: "ACME/Site", Issue: 2, OpenedAt: now.Add(-day)},
	}
	rows := Rows(ruledProjects, data, now)
	wantFailFigures(t, rows, map[string]failFigures{
		"Acme Site": {4, 2, 2, 4, 4},
		"Releases":  {2, 0, 0, 2, 0},
		"Site":      {1, 1, 1, 1, 1},
	})
}

// TestAServiceRowRecoveryCountsTheIssuesNamingIt (forsgren#53, step 2): API's
// row has issue 1, open since yesterday, so one recovery not completed; ADMIN's
// has issue 2, closed after a day, so one recovery of a day; the issue naming
// no service is in the total only.
func TestAServiceRowRecoveryCountsTheIssuesNamingIt(t *testing.T) {
	rows := Rows(serviceProjects, serviceData(), now)
	type figures struct {
		recoveries, unrecovered int
		median                  time.Duration
	}
	for name, want := range map[string]figures{
		"Acme App": {1, 2, day},
		"API":      {0, 1, 0},
		"ADMIN":    {1, 0, day},
	} {
		r := rowNamed(t, rows, name).Recovery
		if got := (figures{r.Recoveries, r.Unrecovered, r.Median}); got != want {
			t.Errorf("%s: want %+v, got %+v", name, want, got)
		}
	}
}
