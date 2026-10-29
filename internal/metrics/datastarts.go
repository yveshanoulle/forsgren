package metrics

// The Data page's table (forsgren#579, step 1): per row, the first time
// forsgren stored data of each kind, so a reader sees where a window longer
// than the stored data is only partly covered.

import (
	"strings"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// DataStart is when forsgren first stored data of one kind for a row: At, or
// the zero time when nothing is stored; PerRepository on a service or rule
// row for a kind that is read per repository.
type DataStart struct {
	At            time.Time
	PerRepository bool
}

// Stored says data of the kind is stored.
func (s DataStart) Stored() bool { return !s.At.IsZero() }

// Late says the first data came after start, Report Start: the window is only
// partly covered.
func (s DataStart) Late(start time.Time) bool { return s.Stored() && s.At.After(start) }

// DataRow is one row of the Data page: a project's total, or one of its
// label, service and rule rows, with the first stored time of each kind.
type DataRow struct {
	Level         Level
	Name, Project string
	// Deployments is the oldest created_at of the stored deployments, Commits
	// the oldest author date of the stored deployed commits, Pushes the oldest
	// pushed_at, Pulls the oldest merged_at of the merged pull requests,
	// Failures the oldest opened_at of the failure issues and Issues the
	// oldest issue event.
	Deployments, Commits, Pushes, Pulls, Failures, Issues DataStart
}

// DataStarts is the Data page's table: Start is Report Start, the first
// minute of the DORA window, and Rows each project's row, then its label,
// service and rule rows, sorted by name ignoring case, as the Week page has.
type DataStarts struct {
	Start time.Time
	Rows  []DataRow
}

// startsSource is what the rows are read from.
type startsSource struct {
	data   Data
	events []history.IssueEvent
}

// DataStartsOf is the Data page's table of projects over data and the stored
// issue events, Report Start from the DORA window ending now.
func DataStartsOf(projects []config.Project, data Data, events []history.IssueEvent, now time.Time) DataStarts {
	source := startsSource{data: data, events: events}
	starts := DataStarts{}
	starts.Start, _ = ReportBounds(data.days(), now)
	for _, p := range projects {
		starts.Rows = append(starts.Rows, source.row(ProjectRow, p, p.Name))
		starts.Rows = append(starts.Rows, labelledRows(p, data, labelBuilders[DataRow]{
			repository: func(only config.Project, project string) DataRow {
				return source.row(LabelRow, only, project)
			},
			service: source.serviceRow,
			name:    func(r DataRow) string { return r.Name },
		})...)
	}
	return starts
}

// row is the row at level of p over all of its repositories' data.
func (s startsSource) row(level Level, p config.Project, project string) DataRow {
	in := repositoriesOf(p)
	row := DataRow{Level: level, Name: p.Name, Project: project}
	row.Deployments, row.Commits = deployedStarts(s.data, in)
	row.Failures = earliest(s.data.Failures, in,
		func(f history.Failure) (string, time.Time) { return f.Repository, f.OpenedAt })
	row.Pushes = earliest(s.data.Pushes, in,
		func(p history.Push) (string, time.Time) { return p.Repository, p.PushedAt })
	row.Pulls = earliest(s.data.Pulls, in,
		func(p history.PullRequest) (string, time.Time) { return p.Repository, p.MergedAt })
	row.Issues = earliest(s.events, in,
		func(e history.IssueEvent) (string, time.Time) { return e.Repository, e.At })
	return row
}

// serviceRow is a service's or a rule's row: its own deployments, the
// commits they shipped and the failure issues of its label; the pushes, pull
// requests and issues are read per repository.
func (s startsSource) serviceRow(only config.Project, project string, own Data, _ []string) DataRow {
	in := repositoriesOf(only)
	row := DataRow{Level: LabelRow, Name: only.Name, Project: project}
	row.Deployments, row.Commits = deployedStarts(own, in)
	row.Failures = earliest(s.data.failuresOf(only.Repositories[0].Name, only.Name), in,
		func(f history.Failure) (string, time.Time) { return f.Repository, f.OpenedAt })
	perRepository := DataStart{PerRepository: true}
	row.Pushes, row.Pulls, row.Issues = perRepository, perRepository, perRepository
	return row
}

// deployedStarts are the first stored deployment and deployed commit of the
// repositories in, over data.
func deployedStarts(data Data, in map[string]bool) (deployments, commits DataStart) {
	deployments = earliest(data.Records, in,
		func(r history.Record) (string, time.Time) { return r.Repository, r.CreatedAt })
	commits = earliest(data.Commits, in,
		func(c history.Commit) (string, time.Time) { return c.Repository, c.AuthoredAt })
	return deployments, commits
}

// repositoriesOf are p's repositories in lower case.
func repositoriesOf(p config.Project) map[string]bool {
	in := map[string]bool{}
	for _, r := range p.Repositories {
		in[strings.ToLower(r.Name)] = true
	}
	return in
}

// earliest is the oldest time of the items of a repository in, compared
// ignoring case; of reads an item's repository and time.
func earliest[T any](items []T, in map[string]bool, of func(T) (string, time.Time)) DataStart {
	var first time.Time
	for _, item := range items {
		if repository, at := of(item); in[strings.ToLower(repository)] {
			first = earlier(first, at)
		}
	}
	return DataStart{At: first}
}
