package metrics

import (
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// The Week table's rows (forsgren#531, step 1, decisions #532 A, #534 A): per
// row the commits and deployments of the DORA window per weekday, Monday
// first, UTC. now is Saturday 3 October 2026 12:00, so the 30-day window
// runs 3 September to 3 October.

// weekProjects is one project: acme/web labelled Website, acme/extra
// labelled Extra, and acme/app with the services API (paths api/) and ADMIN
// (no paths).
func weekProjects() []config.Project {
	return []config.Project{{Name: "Acme Shop", Repositories: []config.Repository{
		{Name: "acme/web", Label: "Website"},
		{Name: "acme/extra", Label: "Extra"},
		{
			Name:     "acme/app",
			Services: map[string]string{"deploy-api": "API", "deploy-admin": "ADMIN"},
			Paths:    map[string][]string{"deploy-api": {"api/"}},
		},
	}}}
}

// utc is the UTC time of the given month, day and clock in 2026.
func utc(month time.Month, d, hour, minute int) time.Time {
	return time.Date(2026, month, d, hour, minute, 0, 0, time.UTC)
}

// weekDeployment is a deployment of repository with the task, in state, at at.
func weekDeployment(repository string, id int64, task string, state history.State, at time.Time) history.Record {
	r := deployedOn(repository, at)
	r.ID, r.Task, r.State = id, task, state
	return r
}

// weekPushCommit is a first-parent commit of repository authored at, brought
// by the push that ended at after.
func weekPushCommit(repository, after, sha string, at time.Time) history.PushCommit {
	return history.PushCommit{Repository: repository, After: after, SHA: sha, AuthoredAt: at,
		Author: "acme-dev", FirstParent: true, Parents: 1}
}

// weekPush is a push of repository that ended at after, at at.
func weekPush(repository, after string, at time.Time) history.Push {
	return history.Push{Repository: repository, PushedAt: at, Before: "b", After: after,
		Kind: history.PushKindPush, Commits: 1}
}

// weekShipped is the commit sha of the deployment id of acme/app, deployed
// at deployed, authored at, on the chain after parent.
func weekShipped(id int64, sha, parent string, authored, deployed time.Time) history.Commit {
	return history.Commit{Repository: "acme/app", Kind: history.KindEnvironment, DeploymentID: id, SHA: sha,
		Parents: []string{parent}, AuthoredAt: authored, DeployedAt: deployed}
}

// weekData is the history behind the Week tests. acme/web: pushed commits
// authored Sunday 23:30 (w1), Monday 00:30 (w2), Saturday (w3), Wednesday
// (w4) and Saturday 1 August, before the window (w0), a branch commit (not
// first-parent) and a commit of a push before the window; deployments
// Sunday 23:30, Monday 00:30, Thursday, a failure and a success before the
// window. acme/app: one pushed commit on Tuesday; deploy-api 1 on Friday
// (commits c1 authored Thursday and touching api/, c2 touching web/, c3 whose
// files are not stored) and 5 on Saturday (c1 again), a failed deploy-api on
// Wednesday; deploy-admin 2 on Saturday and 3 on Sunday. acme/extra: one
// deployment on Wednesday and no commit.
func weekData() Data {
	pushed := now.Add(-time.Hour)
	branch := weekPushCommit("acme/web", "wt", "wb", utc(time.October, 2, 9, 0))
	branch.FirstParent = false
	return Data{
		Records: []history.Record{
			weekDeployment("acme/web", 11, "deploy-web", history.StateSuccess, utc(time.September, 27, 23, 30)),
			weekDeployment("acme/web", 12, "deploy-web", history.StateSuccess, utc(time.September, 28, 0, 30)),
			weekDeployment("acme/web", 13, "deploy-web", history.StateSuccess, utc(time.October, 1, 12, 0)),
			weekDeployment("acme/web", 14, "deploy-web", history.StateFailure, utc(time.September, 29, 12, 0)),
			weekDeployment("acme/web", 15, "deploy-web", history.StateSuccess, utc(time.August, 20, 12, 0)),
			weekDeployment("acme/app", 1, "deploy-api", history.StateSuccess, utc(time.October, 2, 8, 0)),
			weekDeployment("acme/app", 5, "deploy-api", history.StateSuccess, utc(time.October, 3, 7, 0)),
			weekDeployment("acme/app", 4, "deploy-api", history.StateFailure, utc(time.September, 30, 8, 0)),
			weekDeployment("acme/app", 2, "deploy-admin", history.StateSuccess, utc(time.October, 3, 6, 0)),
			weekDeployment("acme/app", 3, "deploy-admin", history.StateSuccess, utc(time.September, 27, 10, 0)),
			weekDeployment("acme/extra", 21, "", history.StateSuccess, utc(time.September, 30, 12, 0)),
		},
		Commits: []history.Commit{
			weekShipped(1, "c1", "root", utc(time.October, 1, 10, 0), utc(time.October, 2, 8, 0)),
			weekShipped(1, "c2", "c1", utc(time.October, 2, 7, 0), utc(time.October, 2, 8, 0)),
			weekShipped(1, "c3", "c2", utc(time.October, 2, 7, 30), utc(time.October, 2, 8, 0)),
			weekShipped(5, "c1", "root", utc(time.October, 1, 10, 0), utc(time.October, 3, 7, 0)),
			weekShipped(2, "d1", "root", utc(time.October, 2, 6, 0), utc(time.October, 3, 6, 0)),
		},
		CommitFiles: []history.CommitFile{
			{Repository: "acme/app", SHA: "c1", Path: "api/x.go"},
			{Repository: "acme/app", SHA: "c2", Path: "web/a.go"},
			{Repository: "acme/app", SHA: "d1", Path: "web/a.go"},
		},
		Pushes: []history.Push{
			weekPush("acme/web", "wt", pushed), weekPush("acme/app", "at", pushed),
			weekPush("acme/web", "wold", now.Add(-40*day)),
		},
		PushCommits: []history.PushCommit{
			weekPushCommit("acme/web", "wt", "w1", utc(time.September, 27, 23, 30)),
			weekPushCommit("acme/web", "wt", "w2", utc(time.September, 28, 0, 30)),
			weekPushCommit("acme/web", "wt", "w3", utc(time.October, 3, 5, 0)),
			weekPushCommit("acme/web", "wt", "w4", utc(time.September, 30, 10, 0)),
			weekPushCommit("acme/web", "wt", "w0", utc(time.August, 1, 9, 0)),
			branch,
			weekPushCommit("acme/web", "wold", "wo", utc(time.August, 20, 9, 0)),
			weekPushCommit("acme/app", "at", "a1", utc(time.September, 29, 9, 0)),
		},
	}
}

// weekRowNamed is the row called name of w.
func weekRowNamed(t *testing.T, w Week, name string) WeekRow {
	t.Helper()
	for _, r := range w.Rows {
		if r.Name == name {
			return r
		}
	}
	t.Fatalf("want a week row named %q, got %d rows", name, len(w.Rows))
	return WeekRow{}
}

// TestWeekRowsAreTotalsThenLabelsLikeTheTbdTable: the project's total, then
// its label rows (repositories, services, rules) sorted ignoring case.
func TestWeekRowsAreTotalsThenLabelsLikeTheTbdTable(t *testing.T) {
	var got []tbdHeading
	for _, r := range WeekOf(weekProjects(), weekData(), now).Rows {
		got = append(got, tbdHeading{r.Level, r.Name, r.Project})
	}
	want := []tbdHeading{
		{ProjectRow, "Acme Shop", "Acme Shop"}, {LabelRow, "ADMIN", "Acme Shop"}, {LabelRow, "API", "Acme Shop"},
		{LabelRow, "Extra", "Acme Shop"}, {LabelRow, "Website", "Acme Shop"},
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

// TestWeekWindowIsTheDoraWindowAsUTCDates: the window's first and last day,
// 30 days back from now by default, and 90 for dora_days 90.
func TestWeekWindowIsTheDoraWindowAsUTCDates(t *testing.T) {
	w := WeekOf(weekProjects(), weekData(), now)
	if want := utc(time.September, 3, 0, 0); !w.Start.Equal(want) {
		t.Errorf("start: want %v, got %v", want, w.Start)
	}
	if want := utc(time.October, 3, 0, 0); !w.End.Equal(want) {
		t.Errorf("end: want %v, got %v", want, w.End)
	}
	data := weekData()
	data.DoraDays = 90
	if got, want := WeekOf(weekProjects(), data, now).Start, utc(time.July, 5, 0, 0); !got.Equal(want) {
		t.Errorf("90-day start: want %v, got %v", want, got)
	}
}

// TestWeekCommitsOfARepositoryRowAreThePushedCommitsAtTheirAuthorDate: the
// TBD Commits set (first-parent commits of the pushes of the window), each
// at its author date, Sunday 23:30 on Sunday and Monday 00:30 on Monday, a
// commit authored before the window on its own weekday, a branch commit and a
// commit of a push before the window left out.
func TestWeekCommitsOfARepositoryRowAreThePushedCommitsAtTheirAuthorDate(t *testing.T) {
	got := weekRowNamed(t, WeekOf(weekProjects(), weekData(), now), "Website")
	if want := [weekdays]int{1, 0, 1, 0, 0, 2, 1}; got.Commits != want {
		t.Errorf("commits Mon..Sun: want %v, got %v", want, got.Commits)
	}
	if got.PerRepository {
		t.Error("a repository row is not Per repository")
	}
}

// TestWeekDeploymentsAreTheSuccessesOfTheWindowAtTheirTime: failures and
// deployments before the window are left out; Sunday 23:30 and Monday 00:30
// fall on their own days.
func TestWeekDeploymentsAreTheSuccessesOfTheWindowAtTheirTime(t *testing.T) {
	got := weekRowNamed(t, WeekOf(weekProjects(), weekData(), now), "Website")
	if want := [weekdays]int{1, 0, 0, 1, 0, 0, 1}; got.Deployments != want {
		t.Errorf("deployments Mon..Sun: want %v, got %v", want, got.Deployments)
	}
}

// TestWeekTotalRowCountsEveryRepositoryOfTheProject: the pushed commits and
// the successful deployments of all repositories, services included.
func TestWeekTotalRowCountsEveryRepositoryOfTheProject(t *testing.T) {
	got := weekRowNamed(t, WeekOf(weekProjects(), weekData(), now), "Acme Shop")
	if want := [weekdays]int{1, 1, 1, 0, 0, 2, 1}; got.Commits != want {
		t.Errorf("commits Mon..Sun: want %v, got %v", want, got.Commits)
	}
	if want := [weekdays]int{1, 0, 1, 1, 1, 2, 2}; got.Deployments != want {
		t.Errorf("deployments Mon..Sun: want %v, got %v", want, got.Deployments)
	}
}

// TestWeekServiceWithPathsCountsItsOwnCommits: the commits its deployments
// shipped that touch its paths, each once at its author date; a commit with
// no stored files yet is left out; its deployments are its task's.
func TestWeekServiceWithPathsCountsItsOwnCommits(t *testing.T) {
	got := weekRowNamed(t, WeekOf(weekProjects(), weekData(), now), "API")
	if want := [weekdays]int{0, 0, 0, 1, 0, 0, 0}; got.Commits != want {
		t.Errorf("commits Mon..Sun: want %v, got %v", want, got.Commits)
	}
	if want := [weekdays]int{0, 0, 0, 0, 1, 1, 0}; got.Deployments != want {
		t.Errorf("deployments Mon..Sun: want %v, got %v", want, got.Deployments)
	}
	if got.PerRepository || !got.Service {
		t.Errorf("want a service with its own commits, got PerRepository %v, Service %v", got.PerRepository, got.Service)
	}
}

// TestWeekServiceWithoutPathsIsPerRepositoryForCommits: no commit counts,
// the deployments are its task's own.
func TestWeekServiceWithoutPathsIsPerRepositoryForCommits(t *testing.T) {
	got := weekRowNamed(t, WeekOf(weekProjects(), weekData(), now), "ADMIN")
	if want := [weekdays]int{}; got.Commits != want {
		t.Errorf("commits Mon..Sun: want %v, got %v", want, got.Commits)
	}
	if want := [weekdays]int{0, 0, 0, 0, 0, 1, 1}; got.Deployments != want {
		t.Errorf("deployments Mon..Sun: want %v, got %v", want, got.Deployments)
	}
	if !got.PerRepository || !got.Service {
		t.Errorf("want Per repository, got PerRepository %v, Service %v", got.PerRepository, got.Service)
	}
	if share, ok := got.WeekendShare(); ok {
		t.Errorf("want no weekend share for Per repository, got %v", share)
	}
}

// TestWeekDeploymentRuleIsPerRepositoryWithoutPathsAndOwnWithPaths: a rule
// counts its own deployments; its commits are the repository's without
// paths, its own with them.
func TestWeekDeploymentRuleIsPerRepositoryWithoutPathsAndOwnWithPaths(t *testing.T) {
	production := config.Deployment{Kind: config.Environment, Name: "production"}
	projects := []config.Project{{Name: "Acme Shop", Repositories: []config.Repository{
		{Name: "acme/app", Rules: []config.Rule{
			{Label: "Prod", Deployment: production},
			{Label: "Prod API", Deployment: production, Paths: []string{"api/"}},
		}},
	}}}
	w := WeekOf(projects, weekData(), now)
	plain, paths := weekRowNamed(t, w, "Prod"), weekRowNamed(t, w, "Prod API")
	if want := [weekdays]int{0, 0, 0, 0, 1, 2, 1}; plain.Deployments != want {
		t.Errorf("Prod deployments Mon..Sun: want %v, got %v", want, plain.Deployments)
	}
	if !plain.PerRepository || !plain.Service {
		t.Errorf("Prod: want Per repository, got PerRepository %v, Service %v", plain.PerRepository, plain.Service)
	}
	if want := [weekdays]int{0, 0, 0, 1, 0, 0, 0}; paths.PerRepository || paths.Commits != want {
		t.Errorf("Prod API: want its own commits %v, got %v (PerRepository %v)", want, paths.Commits, paths.PerRepository)
	}
}

// TestWeekendShareIsWeekendCommitsOverAllCommits: Saturday and Sunday
// commits of the row, deployments never mixed in; a row with no commits has
// no share, which the page shows as a dash.
func TestWeekendShareIsWeekendCommitsOverAllCommits(t *testing.T) {
	w := WeekOf(weekProjects(), weekData(), now)
	for name, want := range map[string]struct {
		share float64
		ok    bool
	}{"Website": {0.6, true}, "API": {0, true}, "Extra": {0, false}} {
		if share, ok := weekRowNamed(t, w, name).WeekendShare(); share != want.share || ok != want.ok {
			t.Errorf("%s: want %v, %v, got %v, %v", name, want.share, want.ok, share, ok)
		}
	}
}

// TestWeekRowWithNoCommitsStillCountsItsDeployments: Extra has none of the
// first and one deployment on Wednesday.
func TestWeekRowWithNoCommitsStillCountsItsDeployments(t *testing.T) {
	extra := weekRowNamed(t, WeekOf(weekProjects(), weekData(), now), "Extra")
	if extra.Commits != [weekdays]int{} {
		t.Errorf("want no commit, got %v", extra.Commits)
	}
	if want := [weekdays]int{0, 0, 1, 0, 0, 0, 0}; extra.Deployments != want {
		t.Errorf("deployments Mon..Sun: want %v, got %v", want, extra.Deployments)
	}
}
