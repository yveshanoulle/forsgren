package metrics

// The TBD table's rows (forsgren#422, step 2): built like the DORA table's
// (rows.go), one function giving every row with all the measures it needs
// instead of a slice per measure, so a row can never be paired with the
// measures of another.
//
//   - a project's total row has every measure over all of the project's data,
//     a commit counted once at its first deployment of any service;
//   - a repository's label row is a project of that one repository, with
//     every measure of its own;
//   - a service's label row has its own deployment measures, over the
//     deployments of its task and the commits they shipped (Data.ofTask): Time
//     to deploy, Deployments, Commits per deployment and Developers. Mainline
//     Interval (decision #449) and the pushes, pull requests and Mainline
//     Lead Time (decision #450, forsgren#463) name no service, so they are
//     marked absent and left empty, for the page to show a dash.

import (
	"math"
	"slices"
	"strings"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
)

// TbdRow is one row of the TBD table: its level, its name (the project's, or
// the label), the project it belongs to, and its measures.
type TbdRow struct {
	Level   Level
	Name    string
	Project string
	// Interval is the Mainline Interval, Lead the PR Lead Time, BotLead the Bot
	// PR Lead Time (forsgren#479), Push the
	// push measures and MainLead the Mainline Lead Time (forsgren#463), which
	// are per repository; Developers, Deploy and Volume are per deployment.
	Interval   MainlineInterval
	Lead       PRLeadTime
	BotLead    PRLeadTime
	Developers Developers
	Push       PushMeasures
	MainLead   MainlineLeadTime
	Deploy     DeployMeasures
	Volume     DeploymentVolume
	// IntervalAbsent says the Mainline Interval is not the row's, and
	// PushAbsent that the push and pull request measures are not (Lead, Push
	// and MainLead): a service row.
	IntervalAbsent, PushAbsent bool
	// DeployPerRepository says a service without paths: its Time to deploy and
	// Commits per deployment are the repository's, which the page words as
	// Per repository (forsgren#496). DeployedCommits is the sum of a
	// service's deployed commits, FilesReading says some of its commits have
	// no stored files yet, so its figures leave them out.
	DeployPerRepository bool
	DeployedCommits     int
	FilesReading        bool
	// Service says the row is a service's: its measures are over the
	// deployments of one task.
	Service bool
}

// tbdSource is what the TBD rows are counted from.
type tbdSource struct {
	data   Data
	now    time.Time
	groups [][]string
}

// TbdRows is the TBD table at the render time now: for each project, in config
// order, its total row, then a row per label its repositories give, sorted by
// label ignoring case, as Rows orders them. groups are the config's
// same_developer groups.
func TbdRows(projects []config.Project, data Data, now time.Time, groups [][]string) []TbdRow {
	source := tbdSource{data: data, now: now, groups: groups}
	var out []TbdRow
	for _, p := range projects {
		out = append(out, source.row(ProjectRow, p, p.Name))
		out = append(out, source.labelRows(p)...)
	}
	return out
}

// labelRows are the rows of p's labels, sorted: each labelled repository as a
// project of its own over all the data, each labelled service over its task's.
func (s tbdSource) labelRows(p config.Project) []TbdRow {
	var rows []TbdRow
	for _, r := range p.Repositories {
		labelled := config.Project{Name: r.Label, Repositories: []config.Repository{r}}
		if r.Label != "" {
			rows = append(rows, s.row(LabelRow, labelled, p.Name))
		}
		for task, label := range r.Services {
			labelled.Name = label
			rows = append(rows, s.serviceRow(labelled, p.Name, task))
		}
	}
	slices.SortFunc(rows, func(a, b TbdRow) int {
		return strings.Compare(strings.ToLower(a.Name), strings.ToLower(b.Name))
	})
	return rows
}

// row is the row at level of the project p, p being the only project, with
// every measure; project is the project the row belongs to.
func (s tbdSource) row(level Level, p config.Project, project string) TbdRow {
	only := []config.Project{p}
	row := s.deployed(only, level, project, nil)
	row.Interval = MainlineIntervals(only, s.data, s.now)[0]
	row.Lead = PRLeadTimes(only, s.data, s.now)[0]
	row.BotLead = BotPRLeadTimes(only, s.data, s.now)[0]
	row.Push = PushMeasuresOf(only, s.data, s.now)[0]
	row.MainLead = MainlineLeadTimesOf(only, s.data, s.now)[0]
	return row
}

// serviceRow is the row of the service task of the repository of p, p being
// the only project: the measures per deployment over the task's data, the
// others absent.
func (s tbdSource) serviceRow(p config.Project, project, task string) TbdRow {
	service := tbdSource{data: s.data.ofTask(p.Repositories[0].Name, task), now: s.now, groups: s.groups}
	scope := scopeOf(p.Repositories[0].Paths[task], s.data.CommitFiles)
	row := service.deployed([]config.Project{p}, LabelRow, project, scope)
	row.IntervalAbsent, row.PushAbsent, row.Service = true, true, true
	row.DeployPerRepository = scope == nil
	row.FilesReading = row.Deploy.Unread > 0
	row.DeployedCommits = deployedCommits(row.Deploy)
	return row
}

// deployedCommits is the sum of the first-parent commits of the deployments
// counted (forsgren#496), a whole number: the mean of whole counts times their
// number.
func deployedCommits(d DeployMeasures) int {
	return int(math.Round(d.PerDeployment.Mean * float64(d.PerDeployment.Count)))
}

// deployed is the row of the only project in only with the measures per
// deployment, counting the commits that touch scope (every commit for nil).
func (s tbdSource) deployed(only []config.Project, level Level, project string, scope *pathScope) TbdRow {
	return TbdRow{
		Level: level, Name: only[0].Name, Project: project,
		Developers: MainlineDevelopers(only, s.data, s.now, s.groups)[0],
		Deploy:     deployMeasures(only, s.data, s.now, scope)[0],
		Volume:     DeploymentVolumes(only, s.data, s.now)[0],
	}
}

// NotesName is the row's name in the Notes list and the pairing of its
// measures (decision D4): "Project: label" for a label row, the project's
// name for a total row. The visible header stays the DORA form.
func (r TbdRow) NotesName() string {
	if r.Level == LabelRow {
		return r.Project + ": " + r.Name
	}
	return r.Name
}

// NoData says whether the row has no data in the DORA window (decision #451,
// A): a service row by the deployment-only rule (ServiceNoData), any other row
// by the project rule (NoData) over its own data.
func (r TbdRow) NoData() bool {
	if r.Service {
		return ServiceNoData(r.Volume, r.Deploy)
	}
	return NoData(r.Volume, r.Deploy, r.Push, r.Lead.PullRequests+r.BotLead.PullRequests)
}
