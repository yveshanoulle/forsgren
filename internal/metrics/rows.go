package metrics

// The page's table (forsgren#38): the four metrics as columns, and as rows
// each project's total, then the rows its config labels. A row's numbers
// come from the four metric functions over the row's own data, as for a
// project of one, so a project's total is the number it had before the
// table, and a labelled row is counted by the very same rules:
//
//   - a repository's label row: all of the repository's deployments,
//     commits and failure issues;
//   - a service's label row: the deployments of the repository with that
//     task, written exactly, and the commits they shipped, joined by
//     repository (ignoring case), kind and deployment ID. A failure issue
//     names no task, so it counts on its project's total row only, and a
//     service's change fail rate comes from its failed deployments alone;
//   - a deployment of no task, or of a task no label names, counts in the
//     total only.

import (
	"cmp"
	"slices"
	"strings"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// Level is where a row of the page's table stands.
type Level int

// The two levels: a project's total, and a row its config labels.
const (
	ProjectRow Level = iota + 1
	LabelRow
)

// Row is one row of the page's table: its level, its name (the project's,
// or the label) and its four numbers.
type Row struct {
	Level      Level
	Name       string
	Frequency  Frequency
	LeadTime   LeadTime
	Recovery   Recovery
	ChangeFail ChangeFailRate
}

// HasDeployments says whether the row has any final deployment, successful
// or failed: a row whose deployments all failed has one open recovery at
// least, and is shown in full, never as no data (decision #35).
func (r Row) HasDeployments() bool { return r.Frequency.HasDeployments() || r.Recovery.Unrecovered > 0 }

// Data is what the rows are counted from: the stored deployments, their
// commits and the failure issues.
type Data struct {
	Records  []history.Record
	Commits  []history.Commit
	Failures []history.Failure
}

// Rows is the page's table at the render time now: for each project, in
// config order, its total row, then a row per label its repositories give,
// sorted by label ignoring case, across its repositories.
func Rows(projects []config.Project, data Data, now time.Time) []Row {
	var out []Row
	for _, p := range projects {
		out = append(out, rowOf(ProjectRow, p, data, now))
		out = append(out, labelRows(p, data, now)...)
	}
	return out
}

// rowOf is the row at level of the project p over data: its four numbers,
// p being the only project.
func rowOf(level Level, p config.Project, data Data, now time.Time) Row {
	only := []config.Project{p}
	return Row{
		Level: level, Name: p.Name,
		Frequency:  DeploymentFrequency(only, data.Records, now)[0],
		LeadTime:   LeadTimes(only, data.Commits, now)[0],
		Recovery:   RecoveryTimes(only, data.Records, now)[0],
		ChangeFail: ChangeFailRates(only, data.Records, data.Failures, now)[0],
	}
}

// labelRows are the rows of p's labels, sorted: each labelled repository as
// a project of its own, over all the data, and each labelled service as
// one over its task's data.
func labelRows(p config.Project, data Data, now time.Time) []Row {
	var rows []Row
	for _, r := range p.Repositories {
		labelled := config.Project{Name: r.Label, Repositories: []config.Repository{r}}
		if r.Label != "" {
			rows = append(rows, rowOf(LabelRow, labelled, data, now))
		}
		for task, label := range r.Services {
			labelled.Name = label
			rows = append(rows, rowOf(LabelRow, labelled, data.ofTask(r.Name, task), now))
		}
	}
	slices.SortFunc(rows, byLabel)
	return rows
}

// byLabel orders rows by name ignoring case; the config refuses two labels
// of a project that differ in case only.
func byLabel(a, b Row) int {
	return cmp.Compare(strings.ToLower(a.Name), strings.ToLower(b.Name))
}

// ofTask is one service's data: the deployments of repository (ignoring
// case) with task, the commits they shipped, and no failure issue.
func (d Data) ofTask(repository, task string) Data {
	var out Data
	shipped := map[deploymentKey]bool{}
	for _, r := range d.Records {
		if strings.EqualFold(r.Repository, repository) && r.Task == task {
			out.Records = append(out.Records, r)
			shipped[keyOf(r.Repository, r.Kind, r.ID)] = true
		}
	}
	for _, c := range d.Commits {
		if shipped[keyOf(c.Repository, c.Kind, c.DeploymentID)] {
			out.Commits = append(out.Commits, c)
		}
	}
	return out
}

// deploymentKey is the deployment a commit was shipped by: the repository,
// lower-case, the kind and the ID, as the commits file keys it.
type deploymentKey struct {
	repository string
	kind       history.Kind
	id         int64
}

func keyOf(repository string, kind history.Kind, id int64) deploymentKey {
	return deploymentKey{strings.ToLower(repository), kind, id}
}
