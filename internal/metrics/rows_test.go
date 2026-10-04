package metrics

import (
	"reflect"
	"slices"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// tableProjects are the made-up projects of the table tests (forsgren#38).
// Acme Shop: acme/web is one row, Website; acme/app names three of its
// tasks, API, ADMIN and IOS; acme/extra has no row. Acme Tools ships
// acme/cli by releases and has no labels.
var tableProjects = []config.Project{
	{Name: "Acme Shop", Repositories: []config.Repository{
		{Name: "acme/web", Label: "Website"},
		{Name: "acme/app", Services: map[string]string{"deploy-api": "API", "deploy-admin": "ADMIN", "deploy-ios": "IOS"}},
		{Name: "acme/extra"},
	}},
	{Name: "Acme Tools", Repositories: []config.Repository{
		{Name: "acme/cli", Deployment: config.Deployment{Kind: config.Release}},
	}},
}

// withTask is the deployment r with its own id and task.
func withTask(r history.Record, id int64, task string) history.Record {
	r.ID, r.Task = id, task
	return r
}

// released is the deployment r as a release.
func released(r history.Record) history.Record {
	r.Kind = history.KindRelease
	return r
}

// appDeployment is a deployment of acme/app to its environment.
func appDeployment(id int64, task string, state history.State, ago time.Duration) history.Record {
	return withTask(deployed("acme/app", state, ago), id, task)
}

// shippedBy is a commit of the deployment id of repository, authored lead
// before it was deployed ago before now.
func shippedBy(repository string, id int64, ago, lead time.Duration) history.Commit {
	return history.Commit{
		Repository: repository, Kind: history.KindEnvironment, DeploymentID: id,
		AuthoredAt: now.Add(-ago - lead), DeployedAt: now.Add(-ago),
	}
}

// tableData is the history of tableProjects at now. acme/app: deploy-api
// twice; deploy-admin once, then a failure recovered 2 hours later; one
// success without a task and one of deploy-worker, which no label names.
// acme/web and acme/extra: one success each. acme/cli: two releases. A
// commit of acme/app's deployments 1, 3 and 6 and of acme/web's; a failure
// issue of acme/app and one of acme/web.
func tableData() Data {
	ok, failure := history.StateSuccess, history.StateFailure
	return Data{
		Records: []history.Record{
			appDeployment(1, "deploy-api", ok, time.Hour),
			appDeployment(2, "deploy-api", ok, 2*day),
			appDeployment(3, "deploy-admin", ok, 3*day),
			appDeployment(4, "deploy-admin", failure, 4*day),
			appDeployment(5, "deploy-admin", ok, 4*day-2*time.Hour),
			appDeployment(6, "", ok, 5*day),
			appDeployment(10, "deploy-worker", ok, day),
			withTask(deployed("acme/web", ok, day), 7, "deploy-web"),
			withTask(deployed("acme/extra", ok, 6*day), 11, ""),
			released(withTask(deployed("acme/cli", ok, 10*day), 8, "v1.0")),
			released(withTask(deployed("acme/cli", ok, 2*day), 9, "v1.1")),
		},
		Commits: []history.Commit{
			shippedBy("acme/app", 1, time.Hour, time.Hour),
			shippedBy("Acme/App", 3, 3*day, day),
			shippedBy("acme/app", 6, 5*day, day),
			shippedBy("acme/web", 7, day, 30*time.Minute),
		},
		Failures: []history.Failure{
			{Repository: "acme/app", Issue: 1, OpenedAt: now.Add(-day)},
			{Repository: "acme/web", Issue: 2, OpenedAt: now.Add(-2 * day)},
		},
	}
}

// heading is a row's level and name, the part of it the table's order shows.
type heading struct {
	level Level
	name  string
}

func headingsOf(rows []Row) []heading {
	out := make([]heading, len(rows))
	for i, r := range rows {
		out[i] = heading{r.Level, r.Name}
	}
	return out
}

// TestRowsAreTotalsThenLabels (forsgren#38): each project's total row, in
// config order, then a row per label the project's repositories give,
// sorted by label ignoring case across the repositories (ADMIN, API, IOS,
// Website), also a label nothing has deployed under yet. A repository
// without labels (acme/extra) and a project without them (Acme Tools) add
// no row.
func TestRowsAreTotalsThenLabels(t *testing.T) {
	got := headingsOf(Rows(tableProjects, tableData(), now))
	want := []heading{
		{ProjectRow, "Acme Shop"},
		{LabelRow, "ADMIN"}, {LabelRow, "API"}, {LabelRow, "IOS"}, {LabelRow, "Website"},
		{ProjectRow, "Acme Tools"},
	}
	if !slices.Equal(got, want) {
		t.Errorf("want %v, got %v", want, got)
	}
}

// TestLabelsSortIgnoringCase: "alpha" sorts before "Beta", which sorts
// before "gamma", whatever their case and their repository.
func TestLabelsSortIgnoringCase(t *testing.T) {
	projects := []config.Project{{Name: "Acme", Repositories: []config.Repository{
		{Name: "acme/b", Services: map[string]string{"x": "gamma", "y": "alpha"}},
		{Name: "acme/a", Label: "Beta"},
	}}}
	got := headingsOf(Rows(projects, Data{}, now))
	want := []heading{{ProjectRow, "Acme"}, {LabelRow, "alpha"}, {LabelRow, "Beta"}, {LabelRow, "gamma"}}
	if !slices.Equal(got, want) {
		t.Errorf("want %v, got %v", want, got)
	}
}

// TestProjectRowsKeepTheirNumbers: a project's row holds exactly what the
// four metric functions give the project over all the data, so the table
// changes no project's number.
func TestProjectRowsKeepTheirNumbers(t *testing.T) {
	data := tableData()
	frequencies := DeploymentFrequency(tableProjects, data.Records, now)
	leadTimes := LeadTimes(tableProjects, data.Commits, now)
	recoveries := RecoveryTimes(tableProjects, data.Records, now)
	changeFails := ChangeFailRates(tableProjects, data.Records, data.Failures, now)
	reworks := ReworkRates(tableProjects, data.Records, data.Failures, now)
	projectRows := projectRowsOf(Rows(tableProjects, data, now))
	if len(projectRows) != len(tableProjects) {
		t.Fatalf("want a row per project, got %v", headingsOf(projectRows))
	}
	for i, r := range projectRows {
		want := Row{ProjectRow, tableProjects[i].Name, frequencies[i], leadTimes[i], recoveries[i], changeFails[i], reworks[i]}
		if !reflect.DeepEqual(r, want) {
			t.Errorf("want\n%+v\ngot\n%+v", want, r)
		}
	}
}

// projectRowsOf is the project rows of rows, in their order.
func projectRowsOf(rows []Row) []Row {
	var out []Row
	for _, r := range rows {
		if r.Level == ProjectRow {
			out = append(out, r)
		}
	}
	return out
}

// rowNamed is the row of rows with name.
func rowNamed(t *testing.T, rows []Row, name string) Row {
	t.Helper()
	for _, r := range rows {
		if r.Name == name {
			return r
		}
	}
	t.Fatalf("want a row %q in %v", name, headingsOf(rows))
	return Row{}
}

// tally is what a row counted, to compare in one step: successes in 30 days,
// commits, recoveries, deployments, failed deployments, failure issues and
// failed changes.
type tally struct {
	last30, commits, recoveries, deployments, failedDeployments, issues, failed int
}

func tallyOf(r Row) tally {
	return tally{
		r.Frequency.Last30, r.LeadTime.Commits, r.Recovery.Recoveries,
		r.ChangeFail.Deployments, r.ChangeFail.FailedDeployments, r.ChangeFail.FailureIssues, r.ChangeFail.Failed,
	}
}

// TestEachRowCountsItsOwnData (forsgren#38): a repository's label row counts
// all its deployments, commits and failure issues; a service's row its
// task's deployments and the commits they shipped, joined by repository
// (ignoring case), kind and deployment ID. A deployment of no task or of a
// task no label names counts in the total only. A failure issue names no
// task, so a service's change fail rate comes from its failed deployments
// alone, and its issues count on the total row.
func TestEachRowCountsItsOwnData(t *testing.T) {
	rows := Rows(tableProjects, tableData(), now)
	cases := []struct {
		name string
		want tally
	}{
		{"Acme Shop", tally{8, 4, 1, 9, 1, 2, 2}},
		{"ADMIN", tally{2, 1, 1, 3, 1, 0, 1}},
		{"API", tally{2, 1, 0, 2, 0, 0, 0}},
		{"IOS", tally{}},
		{"Website", tally{1, 1, 0, 1, 0, 1, 1}},
		{"Acme Tools", tally{2, 0, 0, 2, 0, 0, 0}},
	}
	for _, c := range cases {
		if got := tallyOf(rowNamed(t, rows, c.name)); got != c.want {
			t.Errorf("%s: want %+v, got %+v", c.name, c.want, got)
		}
	}
	if admin := rowNamed(t, rows, "ADMIN"); admin.Recovery.Median != 2*time.Hour {
		t.Errorf("ADMIN: want its recovery in 2 hours, got %v", admin.Recovery.Median)
	}
	if api := rowNamed(t, rows, "API"); api.LeadTime.Median != time.Hour {
		t.Errorf("API: want the lead time of deployment 1's commit, 1 hour, got %v", api.LeadTime.Median)
	}
}

// TestEachRowHasItsReworkCell (forsgren#39): a project's total counts every
// repository's deployments and failure issues, a repository's label row its
// repository's, a service's row only its task's deployments, so only the
// first success after a failed deployment is rework there.
//
// Acme Shop's 8 successes: acme/app's deployments 1 and 10 came while its
// issue was open, 5 recovered deployment 4's failure, and acme/web's 7 came
// while its issue was open. ADMIN holds 3 and 5, of which 5 recovered; API
// none; Website's one is rework through its issue.
func TestEachRowHasItsReworkCell(t *testing.T) {
	rows := Rows(tableProjects, tableData(), now)
	for name, want := range map[string]string{
		"Acme Shop":  "60% · 50% (4 of 8)",
		"ADMIN":      "60% · 50% (1 of 2)",
		"API":        "0% · 0% (0 of 2)",
		"IOS":        "No successful deployments",
		"Website":    "100% · 100% (1 of 1)",
		"Acme Tools": "0% · 0% (0 of 2)",
	} {
		if got := rowNamed(t, rows, name).Rework.Cell(); got != want {
			t.Errorf("%s: want %q, got %q", name, want, got)
		}
	}
}

// TestServiceTasksMatchExactly: a service's task is matched as written, so
// deploy-API is not deploy-api's; the repository is matched ignoring case.
func TestServiceTasksMatchExactly(t *testing.T) {
	ok := history.StateSuccess
	records := []history.Record{
		appDeployment(1, "deploy-api", ok, time.Hour),
		withTask(deployed("Acme/App", ok, time.Hour), 2, "deploy-api"),
		appDeployment(3, "deploy-API", ok, time.Hour),
	}
	rows := Rows(tableProjects[:1], Data{Records: records}, now)
	if api := rowNamed(t, rows, "API"); api.Frequency.Last30 != 2 {
		t.Errorf("want API to count deploy-api of acme/app in any case, 2, got %d", api.Frequency.Last30)
	}
}

// TestARowOfFailuresOnlyIsShown (Yves's ruling on decision #35): a row whose
// deployments all failed has deployments, so the page shows its cells, the
// worst case never looking like no data: no success, the slowest band;
// one recovery not completed yet, its failed deployments one episode; every
// final deployment failed, 100%. A row with no deployment at all has none.
func TestARowOfFailuresOnlyIsShown(t *testing.T) {
	failure := history.StateFailure
	records := []history.Record{
		released(withTask(deployed("acme/cli", failure, 2*day), 1, "v1.0")),
		released(withTask(deployed("acme/cli", failure, day), 2, "v1.1")),
	}
	rows := Rows(tableProjects, Data{Records: records}, now)
	tools := rowNamed(t, rows, "Acme Tools")
	if !tools.HasDeployments() {
		t.Fatalf("want a row of failures only to have deployments, got %+v", tools)
	}
	want := [4]string{
		"Less than once per six months · 0", "No lead time yet", "— · 1 recovery not completed yet",
		"100% · 100% (2 of 2)",
	}
	got := [4]string{tools.Frequency.Cell(), tools.LeadTime.Cell(), tools.Recovery.Cell(), tools.ChangeFail.Cell()}
	if got != want {
		t.Errorf("want %q, got %q", want, got)
	}
	if shop := rowNamed(t, rows, "Acme Shop"); shop.HasDeployments() {
		t.Errorf("want a row with no deployment to have none, got %+v", shop)
	}
}
