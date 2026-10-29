package metrics

import (
	"slices"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// The Data page's rows (forsgren#579, step 1): per row the first time
// forsgren stored data of each kind. now is Saturday 3 October 2026 12:00, so
// the 30-day window starts 3 September 12:00.

// startsData is stored data of weekProjects' repositories, the earliest of
// each kind on acme/app's API service or on acme/web, and older data of a
// repository no project lists.
func startsData() (Data, []history.IssueEvent) {
	data := Data{
		Records: []history.Record{
			weekDeployment("acme/app", 1, "deploy-api", history.StateSuccess, utc(time.September, 20, 9, 0)),
			weekDeployment("acme/app", 2, "deploy-admin", history.StateFailure, utc(time.September, 25, 9, 0)),
			weekDeployment("ACME/Web", 3, "", history.StateSuccess, utc(time.August, 30, 9, 0)),
			weekDeployment("acme/other", 4, "", history.StateSuccess, utc(time.January, 1, 9, 0)),
		},
		Commits: []history.Commit{
			weekShipped(1, "c1", "p0", utc(time.September, 18, 8, 0), utc(time.September, 20, 9, 0)),
			weekShipped(2, "c2", "c1", utc(time.September, 24, 8, 0), utc(time.September, 25, 9, 0)),
		},
		Pushes: []history.Push{
			weekPush("acme/extra", "a1", utc(time.September, 10, 7, 0)),
			weekPush("acme/web", "a2", utc(time.September, 12, 7, 0)),
			weekPush("acme/other", "a3", utc(time.January, 1, 7, 0)),
		},
		Pulls: []history.PullRequest{
			{Repository: "acme/app", Number: 7, MergedAt: utc(time.October, 1, 9, 0)},
			{Repository: "acme/web", Number: 8, MergedAt: utc(time.September, 29, 9, 0)},
		},
	}
	events := []history.IssueEvent{
		{Repository: "acme/web", Issue: 21, Event: history.EventCreated, At: utc(time.September, 1, 6, 0)},
		{Repository: "acme/app", Issue: 22, Event: history.EventCreated, At: utc(time.September, 5, 6, 0)},
		{Repository: "acme/other", Issue: 23, Event: history.EventCreated, At: utc(time.January, 1, 6, 0)},
	}
	return data, events
}

// startsRow is the row named name of the Data page's rows.
func startsRow(t *testing.T, starts DataStarts, name string) DataRow {
	t.Helper()
	for _, r := range starts.Rows {
		if r.Name == name {
			return r
		}
	}
	t.Fatalf("no row %q in %+v", name, starts.Rows)
	return DataRow{}
}

// wantStart fails unless got is the time want, not per repository.
func wantStart(t *testing.T, kind string, got DataStart, want time.Time) {
	t.Helper()
	if got.PerRepository || !got.At.Equal(want) {
		t.Errorf("%s: want %s, got %+v", kind, want, got)
	}
}

// TestDataStartsAreTheEarliestStoredTimePerKind: a project's row has, per
// kind, the earliest time over its repositories (compared ignoring case), and
// nothing of a repository the project does not list.
func TestDataStartsAreTheEarliestStoredTimePerKind(t *testing.T) {
	data, events := startsData()
	starts := DataStartsOf(weekProjects(), data, events, now)
	row := startsRow(t, starts, "Acme Shop")
	if row.Level != ProjectRow || row.Project != "Acme Shop" {
		t.Errorf("want the project row first, got %+v", row)
	}
	wantStart(t, "deployments", row.Deployments, utc(time.August, 30, 9, 0))
	wantStart(t, "commits", row.Commits, utc(time.September, 18, 8, 0))
	wantStart(t, "pushes", row.Pushes, utc(time.September, 10, 7, 0))
	wantStart(t, "pulls", row.Pulls, utc(time.September, 29, 9, 0))
	wantStart(t, "issues", row.Issues, utc(time.September, 1, 6, 0))
	if !starts.Start.Equal(utc(time.September, 3, 12, 0)) {
		t.Errorf("want Report Start 3 September 12:00, got %s", starts.Start)
	}
}

// TestDataStartsOfALabelledRepositoryRow: a labelled repository's row is that
// repository's own data.
func TestDataStartsOfALabelledRepositoryRow(t *testing.T) {
	data, events := startsData()
	web := startsRow(t, DataStartsOf(weekProjects(), data, events, now), "Website")
	if web.Level != LabelRow || web.Project != "Acme Shop" {
		t.Errorf("want Website as a label row of Acme Shop, got %+v", web)
	}
	wantStart(t, "Website deployments", web.Deployments, utc(time.August, 30, 9, 0))
	wantStart(t, "Website pushes", web.Pushes, utc(time.September, 12, 7, 0))
	wantStart(t, "Website issues", web.Issues, utc(time.September, 1, 6, 0))
	if web.Commits.Stored() {
		t.Errorf("want no commits stored for Website, got %+v", web)
	}
}

// TestDataStartsOfAServiceRow: a service row has its own deployments and the
// commits they shipped, and Per
// repository for the pushes, the pull requests and the issues, which are read
// per repository.
func TestDataStartsOfAServiceRow(t *testing.T) {
	data, events := startsData()
	api := startsRow(t, DataStartsOf(weekProjects(), data, events, now), "API")
	wantStart(t, "API deployments", api.Deployments, utc(time.September, 20, 9, 0))
	wantStart(t, "API commits", api.Commits, utc(time.September, 18, 8, 0))
	for kind, got := range map[string]DataStart{"pushes": api.Pushes, "pulls": api.Pulls, "issues": api.Issues} {
		if !got.PerRepository {
			t.Errorf("API %s: want Per repository, got %+v", kind, got)
		}
	}
}

// TestDataStartsListTheRowsAsTheWeekPageDoes: the project, then its label,
// service and rule rows sorted by name ignoring case.
func TestDataStartsListTheRowsAsTheWeekPageDoes(t *testing.T) {
	data, events := startsData()
	var names []string
	for _, r := range DataStartsOf(weekProjects(), data, events, now).Rows {
		names = append(names, r.Name)
	}
	want := []string{"Acme Shop", "ADMIN", "API", "Extra", "Website"}
	if len(names) != len(want) {
		t.Fatalf("want rows %v, got %v", want, names)
	}
	for i := range want {
		if names[i] != want[i] {
			t.Errorf("row %d: want %q, got %q", i, want[i], names[i])
		}
	}
}

// TestADataStartIsLateAfterReportStart: a time after Report Start means the
// window is only partly covered; nothing stored and Per repository are never
// late.
func TestADataStartIsLateAfterReportStart(t *testing.T) {
	start := utc(time.September, 3, 12, 0)
	cases := map[string]struct {
		got  DataStart
		want bool
	}{
		"after":          {DataStart{At: utc(time.September, 3, 12, 1)}, true},
		"at":             {DataStart{At: start}, false},
		"before":         {DataStart{At: utc(time.August, 1, 0, 0)}, false},
		"nothing stored": {DataStart{}, false},
		"per repository": {DataStart{PerRepository: true}, false},
	}
	for name, c := range cases {
		if late := c.got.Late(start); late != c.want {
			t.Errorf("%s: Late = %v, want %v", name, late, c.want)
		}
	}
}

// TestDataStartsWithNothingStoredAreEmpty: a project with no stored data has
// nothing stored of any kind.
func TestDataStartsWithNothingStoredAreEmpty(t *testing.T) {
	projects := []config.Project{{Name: "Acme Old", Repositories: []config.Repository{{Name: "acme/archive"}}}}
	row := startsRow(t, DataStartsOf(projects, Data{}, nil, now), "Acme Old")
	for kind, got := range map[string]DataStart{"deployments": row.Deployments, "commits": row.Commits,
		"pushes": row.Pushes, "pulls": row.Pulls, "issues": row.Issues} {
		if got.Stored() || got.PerRepository {
			t.Errorf("%s: want nothing stored, got %+v", kind, got)
		}
	}
}

// TestDataStartsCommitsTakeAnEarlierPushCommit (forsgren#582, step 1): the
// Commits of a project row is the oldest author date over the deployed
// commits and the push commits; a service row keeps its own deployed commits,
// as push commits are per repository.
func TestDataStartsCommitsTakeAnEarlierPushCommit(t *testing.T) {
	data, events := startsData()
	data.PushCommits = []history.PushCommit{
		{Repository: "ACME/App", After: "a9", SHA: "p1", AuthoredAt: utc(time.September, 15, 8, 0)},
		{Repository: "acme/other", After: "a8", SHA: "p2", AuthoredAt: utc(time.January, 1, 8, 0)},
	}
	starts := DataStartsOf(weekProjects(), data, events, now)
	wantStart(t, "Acme Shop commits", startsRow(t, starts, "Acme Shop").Commits, utc(time.September, 15, 8, 0))
	wantStart(t, "API commits", startsRow(t, starts, "API").Commits, utc(time.September, 18, 8, 0))
}

// TestDataStartsCommitsKeepAnOlderDeployedCommit (forsgren#582, step 1): a
// deployed commit authored before every push commit is the Commits of its
// project row.
func TestDataStartsCommitsKeepAnOlderDeployedCommit(t *testing.T) {
	data, events := startsData()
	data.PushCommits = []history.PushCommit{
		{Repository: "acme/app", After: "a9", SHA: "p1", AuthoredAt: utc(time.September, 19, 8, 0)},
	}
	row := startsRow(t, DataStartsOf(weekProjects(), data, events, now), "Acme Shop")
	wantStart(t, "Acme Shop commits", row.Commits, utc(time.September, 18, 8, 0))
}

// TestDataStartsMarkPushesCutAtThePageCap (forsgren#583, step 1): a row with
// a repository whose push read stopped at the page cap has its Pushes cut,
// and its Commits too when the push commits give the oldest date; a
// repository label row of another repository is not cut, and a service row
// reads Per repository for pushes and its own deployed commits.
func TestDataStartsMarkPushesCutAtThePageCap(t *testing.T) {
	data, events := startsData()
	data.PushCommits = []history.PushCommit{
		{Repository: "acme/app", After: "a9", SHA: "p1", AuthoredAt: utc(time.September, 15, 8, 0)},
	}
	data.PushesCut = history.Reach{"acme/app": utc(time.September, 15, 9, 0)}
	starts := DataStartsOf(weekProjects(), data, events, now)
	shop := startsRow(t, starts, "Acme Shop")
	if !shop.Pushes.Cut || !shop.Commits.Cut {
		t.Errorf("want Acme Shop's pushes and commits cut, got %+v and %+v", shop.Pushes, shop.Commits)
	}
	if web := startsRow(t, starts, "Website"); web.Pushes.Cut {
		t.Errorf("want Website's pushes not cut, got %+v", web.Pushes)
	}
	if api := startsRow(t, starts, "API"); api.Commits.Cut || api.Pushes.Cut {
		t.Errorf("want API not cut, got %+v and %+v", api.Commits, api.Pushes)
	}
}

// shopWithPushCommit is Acme Shop's row of startsData with one push commit
// of acme/app authored on 19 September at hour, and mark set on data.
func shopWithPushCommit(t *testing.T, hour int, mark func(*Data)) DataRow {
	t.Helper()
	data, events := startsData()
	data.PushCommits = []history.PushCommit{
		{Repository: "acme/app", After: "a9", SHA: "p1", AuthoredAt: utc(time.September, 15+hour/24, hour%24, 0)},
	}
	mark(&data)
	return startsRow(t, DataStartsOf(weekProjects(), data, events, now), "Acme Shop")
}

// TestDataStartsCommitsAreNotCutWhenADeployedCommitIsOlder (forsgren#583,
// step 1): the deployed commits give the date, which the push read does not
// limit.
func TestDataStartsCommitsAreNotCutWhenADeployedCommitIsOlder(t *testing.T) {
	shop := shopWithPushCommit(t, 4*24+8, func(d *Data) {
		d.PushesCut = history.Reach{"acme/app": utc(time.September, 19, 9, 0)}
	})
	if shop.Commits.Cut || !shop.Pushes.Cut {
		t.Errorf("want Acme Shop's pushes cut and its commits not, got %+v and %+v", shop.Pushes, shop.Commits)
	}
}

// TestDataStartsMarkWhereGitHubKeepsNoOlderActivity (forsgren#583, step 3): a
// row with a repository whose fill ended at GitHub's end of the list has its
// Pushes marked so, and its Commits when the push commits give the date; it
// is not cut.
func TestDataStartsMarkWhereGitHubKeepsNoOlderActivity(t *testing.T) {
	shop := shopWithPushCommit(t, 8, func(d *Data) {
		d.PushesGitHubEnd = history.Reach{"acme/app": utc(time.September, 15, 9, 0)}
	})
	marks := []bool{shop.Pushes.GitHubEnd, shop.Commits.GitHubEnd, !shop.Pushes.Cut}
	if slices.Contains(marks, false) {
		t.Errorf("want Acme Shop's pushes and commits at GitHub's end, not cut, got %+v and %+v", shop.Pushes, shop.Commits)
	}
}
