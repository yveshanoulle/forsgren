package metrics

import (
	"maps"
	"slices"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// The TBD table's rows (forsgren#422, step 2, decisions #449, #450): the
// total row of each project, then a row per label, with every measure.

// tbdHeading is a TBD row's level, name and project.
type tbdHeading struct {
	level   Level
	name    string
	project string
}

func tbdRowNamed(t *testing.T, rows []TbdRow, name string) TbdRow {
	t.Helper()
	for _, r := range rows {
		if r.Name == name {
			return r
		}
	}
	t.Fatalf("want a TBD row named %q, got %d rows", name, len(rows))
	return TbdRow{}
}

// tbdData is tableData's deployments with one commit both deploy-api
// (deployment 1, 1 h ago) and deploy-admin (deployment 3, 3 days ago) shipped,
// authored 4 days ago, and one push of acme/web and one of acme/app with the
// commit it brought.
func tbdData() Data {
	data := tableData()
	data.Commits, data.Failures = nil, nil
	shared := func(id int64, ago time.Duration) history.Commit {
		c := shippedBy("acme/app", id, ago, 4*day-ago)
		c.SHA, c.Author = "shared", "acme-dev"
		return c
	}
	data.Commits = append(data.Commits, shared(1, time.Hour), shared(3, 3*day))
	push := func(repository, after string) history.Push {
		return history.Push{Repository: repository, PushedAt: now.Add(-time.Hour), Before: "b", After: after,
			Kind: history.PushKindPush, Commits: 1}
	}
	data.Pushes = []history.Push{push("acme/web", "w1"), push("acme/app", "a1")}
	data.PushCommits = []history.PushCommit{
		{Repository: "acme/web", After: "w1", SHA: "w1", AuthoredAt: now.Add(-2 * time.Hour), Author: "acme-dev",
			FirstParent: true, Parents: 1},
		{Repository: "acme/app", After: "a1", SHA: "a1", AuthoredAt: now.Add(-2 * time.Hour), Author: "acme-dev",
			FirstParent: true, Parents: 1},
	}
	return data
}

// TestTbdRowsAreTotalsThenLabelsLikeTheDoraTable: each project's total row,
// in config order, then its label rows sorted by label ignoring case, each
// with the project it belongs to.
func TestTbdRowsAreTotalsThenLabelsLikeTheDoraTable(t *testing.T) {
	var got []tbdHeading
	for _, r := range TbdRows(tableProjects, tbdData(), now, nil) {
		got = append(got, tbdHeading{r.Level, r.Name, r.Project})
	}
	want := []tbdHeading{
		{ProjectRow, "Acme Shop", "Acme Shop"}, {LabelRow, "ADMIN", "Acme Shop"}, {LabelRow, "API", "Acme Shop"},
		{LabelRow, "IOS", "Acme Shop"}, {LabelRow, "Website", "Acme Shop"}, {ProjectRow, "Acme Tools", "Acme Tools"},
	}
	if len(got) != len(want) {
		t.Fatalf("want %v, got %v", want, got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("row %d: want %v, got %v", i+1, want[i], got[i])
		}
	}
}

// tbdFigures are the counts of a row's measures per deployment and per
// repository.
type tbdFigures struct {
	Deployments, Timed, Developers, Pushes int
	IntervalAbsent, PushAbsent             bool
}

func figuresOf(r TbdRow) tbdFigures {
	return tbdFigures{r.Volume.Count, r.Deploy.Commits, r.Developers.Count, r.Push.Pushes,
		r.IntervalAbsent, r.PushAbsent}
}

// TestAServiceTbdRowCountsItsOwnDeployments: the API row has the two
// deployments of deploy-api, its one commit timed at its own deployment
// (author date: no lineage), one developer; the Mainline Interval and the
// push measures are marked absent and left empty.
func TestAServiceTbdRowCountsItsOwnDeployments(t *testing.T) {
	api := tbdRowNamed(t, TbdRows(tableProjects, tbdData(), now, nil), "API")
	want := tbdFigures{Deployments: 2, Timed: 1, Developers: 1, IntervalAbsent: true, PushAbsent: true}
	if got := figuresOf(api); got != want {
		t.Errorf("want %+v, got %+v", want, got)
	}
	if absent := [4]int{api.Push.Commits, api.Lead.PullRequests, api.BotLead.PullRequests,
		api.Interval.Commits}; absent != [4]int{} {
		t.Errorf("want nothing in the absent measures of a service row, got %+v", api)
	}
}

// TestTheTotalTbdRowCountsACommitOnceAtItsFirstDeploymentOfAnyService: the
// shared commit was shipped by deploy-admin 3 days ago and deploy-api 1 h
// ago, authored 4 days ago; the total times it once, at the earlier (1 day),
// as ADMIN does, while API times it at its own deployment (3 d 23 h). The
// total has the pushes of both repositories and no absent measure.
func TestTheTotalTbdRowCountsACommitOnceAtItsFirstDeploymentOfAnyService(t *testing.T) {
	rows := TbdRows(tableProjects, tbdData(), now, nil)
	got := []time.Duration{
		rows[0].Deploy.TimeToDeploy.Mean, tbdRowNamed(t, rows, "ADMIN").Deploy.TimeToDeploy.Mean,
		tbdRowNamed(t, rows, "API").Deploy.TimeToDeploy.Mean,
	}
	want := []time.Duration{day, day, 4*day - time.Hour}
	if !slices.Equal(got, want) {
		t.Errorf("want the shared commit at %v in the total, ADMIN and API, got %v", want, got)
	}
	if wantTotal := (tbdFigures{Deployments: 8, Timed: 1, Developers: 1, Pushes: 2}); figuresOf(rows[0]) != wantTotal {
		t.Errorf("want %+v, got %+v", wantTotal, figuresOf(rows[0]))
	}
}

// TestARepositoryLabelTbdRowIsAOneRepositoryProject: Website is acme/web
// alone, with its own push and deployment and no measure absent.
func TestARepositoryLabelTbdRowIsAOneRepositoryProject(t *testing.T) {
	web := tbdRowNamed(t, TbdRows(tableProjects, tbdData(), now, nil), "Website")
	if want := (tbdFigures{Deployments: 1, Pushes: 1}); figuresOf(web) != want {
		t.Errorf("want %+v, got %+v", want, figuresOf(web))
	}
}

// TestTbdRowsHaveNoDataByTheirOwnRule (forsgren#422, step 3, decision #451):
// a service with no deployment in the window has none although its repository
// was pushed to, a repository label and the total use the project rule, and a
// service that deployed has data.
func TestTbdRowsHaveNoDataByTheirOwnRule(t *testing.T) {
	data := tbdData()
	data.Records = data.Records[:2] // deployments 1 and 2 of deploy-api
	rows := TbdRows(tableProjects, data, now, nil)
	got := map[string]bool{}
	for _, name := range []string{"Acme Shop", "ADMIN", "API", "Website", "Acme Tools"} {
		got[name] = tbdRowNamed(t, rows, name).NoData()
	}
	want := map[string]bool{"Acme Shop": false, "ADMIN": true, "API": false, "Website": false, "Acme Tools": true}
	if !maps.Equal(got, want) {
		t.Errorf("want no data in %v, got %v", want, got)
	}
}

// TestTbdRowNamesInTheNotesList: a label row is Project: label, a total row
// its project's name.
func TestTbdRowNamesInTheNotesList(t *testing.T) {
	rows := TbdRows(tableProjects, tbdData(), now, nil)
	got := []string{rows[0].NotesName(), tbdRowNamed(t, rows, "API").NotesName(),
		tbdRowNamed(t, rows, "Website").NotesName()}
	want := []string{"Acme Shop", "Acme Shop: API", "Acme Shop: Website"}
	if !slices.Equal(got, want) {
		t.Errorf("want %q, got %q", want, got)
	}
}

// TestTbdRowsCarryTheBotPRLeadTimeBesideThePRLeadTime (forsgren#479, step 1): a
// total row and a repository label row have the lead time of the pull requests
// a bot opened (BotLead) beside the people's (Lead), each over the row's own
// repositories, bots of unknown author in neither; a service row leaves it
// empty, absent like Lead.
func TestTbdRowsCarryTheBotPRLeadTimeBesideThePRLeadTime(t *testing.T) {
	h := time.Hour
	data := tbdData()
	data.Pulls = []history.PullRequest{
		mergedPull("acme/web", 1, 2*h, h),
		openedBy(mergedPull("acme/web", 2, 4*h, h), history.ByBot),
		openedBy(mergedPull("acme/app", 3, 6*h, h), history.ByBot),
		openedBy(mergedPull("acme/app", 4, 8*h, h), history.BotUnknown),
	}
	rows := TbdRows(tableProjects, data, now, nil)
	wantPullCounts(t, rows)
	if web := tbdRowNamed(t, rows, "Website").BotLead; web.Mean != 4*h || web.Project != "Website" {
		t.Errorf("want the Website bot lead time 4 h, got %+v", web)
	}
	if shop := rows[0].BotLead; shop.Mean != 5*h || shop.Median != 5*h {
		t.Errorf("want the Acme Shop bot lead time 5 h, got %+v", shop)
	}
}

// wantPullCounts holds the pull requests of the people and of the bots of three
// rows of TestTbdRowsCarryTheBotPRLeadTimeBesideThePRLeadTime to their counts.
func wantPullCounts(t *testing.T, rows []TbdRow) {
	t.Helper()
	type pair struct{ human, bots int }
	got := map[string]pair{}
	for _, name := range []string{"Acme Shop", "Website", "API"} {
		r := tbdRowNamed(t, rows, name)
		got[name] = pair{r.Lead.PullRequests, r.BotLead.PullRequests}
	}
	want := map[string]pair{"Acme Shop": {1, 2}, "Website": {1, 1}, "API": {}}
	if !maps.Equal(got, want) {
		t.Errorf("want pull requests (people, bots) %v, got %v", want, got)
	}
}
