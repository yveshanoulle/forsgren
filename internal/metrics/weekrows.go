package metrics

// The Week table's rows (forsgren#531, step 1, decisions #532 A and #534 A):
// per row, the commits and the deployments of the DORA window per weekday,
// Monday first, UTC. Built like TbdRows (tbdrows.go): a project's total row,
// then a row per label, service and rule, sorted by name ignoring case.
//
//   - a commit counts at its author date, a deployment at its time, both UTC
//     (decision #532 A);
//   - the commits of a total row and of a repository's label row are the set
//     the TBD Commits column counts (PushMeasures.Commits): the distinct
//     first-parent commits of the pushes pushed in the window, by repository
//     (ignoring case) and SHA, a commit authored before the window counted
//     at its own author date all the same;
//   - a service or rule row without paths has no commits of its own: it is
//     PerRepository, its commit counts stay 0 and the page writes
//     Per repository (decision #534 A; its day cells write an en dash for
//     the commits, decision #539 A);
//   - a service or rule row with paths counts its own commits, those that
//     the TBD page's Deployed commits count (the same pathScope over
//     Data.CommitFiles): the distinct commits of the row's deployments that
//     touch a path, each once, at its first deployment in the window; a
//     commit with no stored files yet is left out. Push commits have no
//     stored files, so the deployed commits are the only set a path can
//     judge;
//   - the deployments of every row are its successful deployments created in
//     the window (as DeploymentFrequency.InWindow counts them), over the
//     row's own data for a service or rule; the Deployments cells and the
//     highest Deploys share count them plus the failed ones (forsgren#601);
//   - the page shows a Total and, per weekday, the share of the row's commits
//     and of its deployments (forsgren#540, decision #541; the weekend share
//     column is gone).
//
// sub_rows: false is the page's to honour (Data.leavesOut), as for TbdRows.

import (
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// weekdays is the number of weekday columns, Monday first.
const weekdays = 7

// WeekRow is one row of the Week table: its level, its name (the project's,
// or the label), the project it belongs to, the commits and the deployments
// per weekday, Monday first.
type WeekRow struct {
	Level                Level
	Name, Project        string
	Commits, Deployments [weekdays]int
	// Failed are the deployments of state failure created in the window, per
	// weekday (forsgren#545, decision #546).
	Failed [weekdays]int
	// PerRepository says a service or rule without paths: its commits are the
	// repository's, so none is counted on the row.
	PerRepository bool
	// Service says the row is a service's or a rule's.
	Service bool
}

// Week is the Week table: the first and last day of the DORA window as UTC
// dates, and the rows.
type Week struct {
	Start, End time.Time
	Rows       []WeekRow
}

// weekdayOf is the column of t: 0 for Monday to 6 for Sunday, UTC.
func weekdayOf(t time.Time) int { return (int(t.UTC().Weekday()) + weekdays - 1) % weekdays }

// weekSource is what the Week rows are counted from.
type weekSource struct {
	data Data
	now  time.Time
}

// WeekOf is the Week table at the render time now: for each project, in
// config order, its total row, then a row per label its repositories give.
func WeekOf(projects []config.Project, data Data, now time.Time) Week {
	source := weekSource{data: data, now: now}
	week := Week{}
	week.Start, week.End = ReportBounds(data.days(), now)
	for _, p := range projects {
		week.Rows = append(week.Rows, source.row(ProjectRow, p, p.Name))
		week.Rows = append(week.Rows, source.labelRows(p)...)
	}
	return week
}

// labelRows are the rows of p's labels, sorted by name ignoring case.
func (s weekSource) labelRows(p config.Project) []WeekRow {
	return labelledRows(p, s.data, labelBuilders[WeekRow]{
		repository: func(only config.Project, project string) WeekRow { return s.row(LabelRow, only, project) },
		service:    s.serviceRow,
		name:       func(r WeekRow) string { return r.Name },
	})
}

// row is the row at level of the project p, p being the only project: its
// pushed commits and its deployments.
func (s weekSource) row(level Level, p config.Project, project string) WeekRow {
	row := WeekRow{Level: level, Name: p.Name, Project: project}
	row.Deployments, row.Failed = s.deploymentDays(p, s.data)
	index := indexOf([]config.Project{p})
	tips, _ := pushesInWindow([]PushMeasures{{}}, index, s.data, s.now)
	for _, c := range commitsOfPushes(index, s.data, tips) {
		row.Commits[weekdayOf(c.authored)]++
	}
	return row
}

// serviceRow is the row of a service or a rule of the repository of p, over
// its own data: its deployments, and its commits when it has paths.
func (s weekSource) serviceRow(p config.Project, project string, own Data, paths []string) WeekRow {
	row := WeekRow{Level: LabelRow, Name: p.Name, Project: project, Service: true}
	row.Deployments, row.Failed = s.deploymentDays(p, own)
	scope := scopeOf(paths, own.CommitFiles)
	row.PerRepository = scope == nil
	if !row.PerRepository {
		row.Commits = s.deployedCommitDays(p, own, scope)
	}
	return row
}

// deploymentDays are, per weekday, the successful deployments and the failed
// ones (state failure) of data's records of the repositories of p created in the window
// (forsgren#545, decision #546).
func (s weekSource) deploymentDays(p config.Project, data Data) (successes, failed [weekdays]int) {
	index, in := indexOf([]config.Project{p}), data.window()
	for _, r := range data.Records {
		_, listed := index.of(r.Repository)
		if !listed || !in.holds(r.CreatedAt, s.now) {
			continue
		}
		day := weekdayOf(r.CreatedAt)
		switch r.State {
		case history.StateSuccess:
			successes[day]++
		case history.StateFailure:
			failed[day]++
		}
	}
	return successes, failed
}

// deployedCommitDays are the commits of data's deployments that touch scope,
// each once at its first deployment in the window, per weekday of its author
// date.
func (s weekSource) deployedCommitDays(p config.Project, data Data, scope *pathScope) [weekdays]int {
	var days [weekdays]int
	counting := directCounting{index: indexOf([]config.Project{p}), lines: lineageOf(data.Commits), scope: scope}
	authored := map[string]time.Time{}
	for _, c := range data.Commits {
		authored[commitKey(c.Repository, c.SHA)] = c.AuthoredAt
	}
	in := data.window()
	for key, first := range firstDeployments(data.Commits, counting) {
		if in.holds(first.deployed, s.now) {
			days[weekdayOf(authored[key])]++
		}
	}
	return days
}

// notAttributed is what a day cell of a row Per repository writes for its
// commits: an en dash, the commits being counted at repository level, not
// zero (decision #539 A, Yves 2026-10-27).
const notAttributed = "\u2013"

// sum is the total of the per-weekday counts.
func sum(days [weekdays]int) int {
	total := 0
	for _, n := range days {
		total += n
	}
	return total
}

// CommitsTotalCell is the row's commits of the window as a count (the
// thousands rule of forsgren#528); an en dash for a PerRepository row, whose
// commits are counted at repository level (forsgren#540, decisions #539 A and
// #541).
func (r WeekRow) CommitsTotalCell() string {
	if r.PerRepository {
		return notAttributed
	}
	return GroupDigits(sum(r.Commits))
}

// DeploymentsTotalCell is the row's deployments of the window, successful
// plus failed, as a count (forsgren#601).
func (r WeekRow) DeploymentsTotalCell() string { return GroupDigits(sum(r.deployed())) }

// deployed are the row's deployments per weekday that the Week page counts:
// the successful and the failed ones, not the other states (forsgren#601).
func (r WeekRow) deployed() [weekdays]int { return addDays(r.Deployments, r.Failed) }

// CommitsShareCell is the share of the row's commits on weekday day (0
// Monday to 6 Sunday), written as the TBD shares are (shareOf); a dash for a row with no commits, an en
// dash for a PerRepository row.
func (r WeekRow) CommitsShareCell(day int) string {
	if r.PerRepository {
		return notAttributed
	}
	return shareOf(r.Commits[day], sum(r.Commits))
}

// DeploymentsShareCell is the share of the row's deployments, successful plus
// failed, on weekday day, as CommitsShareCell writes it; a dash for a row with
// none.
func (r WeekRow) DeploymentsShareCell(day int) string {
	return shareOf(r.rated(day), sum(r.deployed()))
}
