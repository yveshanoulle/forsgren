package page

import (
	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// The TBD page's spread groups (forsgren#474): Mainline Interval, Mainline
// Lead Time, Time to main, PR Lead Time, Bot PR Lead Time, Time to deploy,
// Commits per push and Commits per deployment are each written by one
// template define (spreadgroup for a row, the spreadhead defines for the
// headers) from a spreadGroup or a spreadHead built here, so the groups differ
// in data only and the lists below are the one place that names them.

// spreadColspan is how many columns a group spans when the table shows the
// mean, the median and the 90th percentile.
const spreadColspan = 3

// spreadID names a group, so a switch can filter it out of the lists.
type spreadID int

const (
	idInterval spreadID = iota
	idMainLead
	idTimeToMain
	idPRLeadTime
	idBotPRLeadTime
	idTimeToDeploy
	idPerPush
	idPerDeployment
	spreadGroups // how many groups there are
)

// hiddenGroups says, by group, whether the config turns it off (forsgren#482,
// decisions #480 and #481).
type hiddenGroups [spreadGroups]bool

// hiddenGroups are the groups of d that its switches turn off: the one place
// that maps a switch to its group.
func (d Data) hiddenGroups() hiddenGroups {
	var h hiddenGroups
	h[idTimeToMain], h[idPRLeadTime], h[idBotPRLeadTime] = d.HideTbdTimeToMain, d.HideTbdPRLeadTime, d.HideTbdBotPRLeadTime
	return h
}

// has says whether the group is turned off.
func (h hiddenGroups) has(id spreadID) bool { return h[id] }

// count is how many groups are turned off.
func (h hiddenGroups) count() int {
	n := 0
	for _, off := range h {
		if off {
			n++
		}
	}
	return n
}

// shown are the items whose group is not turned off, in their order.
func shown[T any](h hiddenGroups, items []T, idOf func(T) spreadID) []T {
	var out []T
	for _, item := range items {
		if !h.has(idOf(item)) {
			out = append(out, item)
		}
	}
	return out
}

// spreadGroup is one group of a row: the sentence in place of its figures, or
// its cells, the three of tbd_figures: all or the one of the median alone.
type spreadGroup struct {
	// ID is the group.
	ID spreadID
	// State is the sentence across the group, empty when it has its figures.
	State string
	// Colspan is the columns State spans, 0 for none.
	Colspan int
	// Cells are the figures, noted or plain.
	Cells []metrics.NotedCell
}

// spreadHead is one group of the headers.
type spreadHead struct {
	// ID is the group.
	ID spreadID
	// Title is the group's header.
	Title string
	// Subject names the group in the aria-label of its mean, median and p90
	// headers (all).
	Subject string
	// MedianLabel is the aria-label of the header of the median alone.
	MedianLabel string
}

// spreadHeads are the headers of the eight groups, in the table's order: the
// first six sit before Volume, the last two after it.
var spreadHeads = [...]spreadHead{
	{idInterval, "Mainline Interval", "mainline interval", "median mainline interval"},
	{idMainLead, "Mainline Lead Time", "mainline lead time", "median mainline lead time"},
	{idTimeToMain, "Time to main per commit", "time to main", "median time to main per commit"},
	{idPRLeadTime, "PR Lead Time", "PR lead time", "median PR lead time"},
	{idBotPRLeadTime, "Bot PR Lead Time", "bot PR lead time", "median bot PR lead time"},
	{idTimeToDeploy, "Time to deploy per commit", "time to deploy", "median time to deploy per commit"},
	{idPerPush, "Commits per push", "commits per push", "median commits per push"},
	{idPerDeployment, "Commits per deployment", "commits per deployment", "median commits per deployment"},
}

// beforeVolume is how many of spreadHeads come before the Volume group.
const beforeVolume = 6

// headID is the group of a header.
func headID(h spreadHead) spreadID { return h.ID }

// TbdGroupHeads are the headers of the groups before Volume that are shown.
func (d Data) TbdGroupHeads() []spreadHead {
	return shown(d.hiddenGroups(), spreadHeads[:beforeVolume], headID)
}

// TbdBatchHeads are the headers of the groups after Volume.
func (d Data) TbdBatchHeads() []spreadHead {
	return shown(d.hiddenGroups(), spreadHeads[beforeVolume:], headID)
}

// upperFigures are the median and p90 cells, which a spread whose mean cell
// carries notes has beside it.
type upperFigures interface {
	MedianCell() string
	P90Cell() string
}

// figures is a spread's three cells.
type figures interface {
	MeanCell() string
	upperFigures
}

// notedFigures are the cells that carry a measure's notes: the mean's for the
// table that shows all three figures, the median's for the one that shows the
// median alone.
type notedFigures interface {
	MeanCell() metrics.NotedCell
	MedianNotedCell() metrics.NotedCell
}

// plain is a cell without notes.
func plain(value string) metrics.NotedCell { return metrics.NotedCell{Value: value} }

// colspanOf is the span of a state across a group.
func colspanOf(all bool) int {
	if all {
		return spreadColspan
	}
	return 0
}

// plainGroup is the group of a spread whose cells carry no notes.
func plainGroup(all bool, state string, s figures) spreadGroup {
	cells := []metrics.NotedCell{plain(s.MedianCell())}
	if all {
		cells = []metrics.NotedCell{plain(s.MeanCell()), plain(s.MedianCell()), plain(s.P90Cell())}
	}
	return spreadGroup{State: state, Colspan: colspanOf(all), Cells: cells}
}

// notedGroup is the group whose mean cell, or median cell alone, carries the
// notes of noted; rest has the median and p90 cells.
func notedGroup(all bool, state string, noted notedFigures, rest upperFigures) spreadGroup {
	cells := []metrics.NotedCell{noted.MedianNotedCell()}
	if all {
		cells = []metrics.NotedCell{noted.MeanCell(), plain(rest.MedianCell()), plain(rest.P90Cell())}
	}
	return spreadGroup{State: state, Colspan: colspanOf(all), Cells: cells}
}

// as names the group g is.
func (g spreadGroup) as(id spreadID) spreadGroup {
	g.ID = id
	return g
}

// groupID is the group of a spreadGroup.
func groupID(g spreadGroup) spreadID { return g.ID }

// MainGroups are the groups that a service row writes as Per repository:
// Mainline Interval, Mainline Lead Time, Time to main, PR Lead Time and Bot PR
// Lead Time, less those the config turns off.
func (r TbdRow) MainGroups() []spreadGroup {
	a := r.all
	return shown(r.hidden, []spreadGroup{
		notedGroup(a, r.Interval.State(), r.Interval, r.Interval).as(idInterval),
		notedGroup(a, r.MainLead.State(), r.MainLead, r.MainLead.Lead).as(idMainLead),
		plainGroup(a, r.Push.State(), r.Push.TimeToMain).as(idTimeToMain),
		notedGroup(a, r.LeadState(), r.Lead, r.Lead).as(idPRLeadTime),
		notedGroup(a, r.BotLeadState(), r.BotLead, r.BotLead).as(idBotPRLeadTime),
	}, groupID)
}

// MainSpan is the columns the shown MainGroups have, which a service row's Per
// repository cell spans.
func (r TbdRow) MainSpan() int {
	n := 0
	for _, g := range r.MainGroups() {
		n += len(g.Cells)
	}
	return n
}

// DeployGroups are the groups after the push and pull request ones: Time to
// deploy per commit, which a service without paths writes as Per repository
// (forsgren#496).
func (r TbdRow) DeployGroups() []spreadGroup {
	return []spreadGroup{r.deployGroup(r.Deploy.TimeToDeploy).as(idTimeToDeploy)}
}

// deployGroup is the group of a measure per deployment: Per repository for a
// service without paths, else its figures, the first cell carrying the notes
// of the row's files (forsgren#496).
func (r TbdRow) deployGroup(s figures) spreadGroup {
	g := plainGroup(r.all, r.deployState(), s)
	g.Cells[0].Notes = r.filesNotes()
	return g
}

// deployState is the sentence in place of the figures of a measure per
// deployment: Per repository for a service without paths, else none.
func (r TbdRow) deployState() string {
	if r.DeployPerRepository {
		return r.PerRepositorySentence()
	}
	return ""
}

// BatchGroups are the groups after Volume: Commits per push, which a service
// row writes as Per repository, and Commits per deployment, which a service
// without paths writes so too.
func (r TbdRow) BatchGroups() []spreadGroup {
	state := r.Push.State()
	if r.PerRepository() {
		state = r.PerRepositorySentence()
	}
	return []spreadGroup{
		plainGroup(r.all, state, r.Push.PerPush).as(idPerPush),
		r.deployGroup(r.Deploy.PerDeployment).as(idPerDeployment),
	}
}

// VolumeGroups are the cells of Volume before Deployments: Commits and Pushes
// (forsgren#518). A service row writes Per repository across both, which are
// the repository's.
func (r TbdRow) VolumeGroups() []spreadGroup {
	if !r.PerRepository() {
		return []spreadGroup{{Cells: []metrics.NotedCell{plain(r.Push.CommitsCell()), plain(r.Push.PushesCell())}}}
	}
	return []spreadGroup{{State: r.PerRepositorySentence(), Colspan: 2}}
}

// DeployedCommitsGroups are the cells of Volume after Deployments: Deployed
// commits (forsgren#513, decision #495). A service row writes Per repository
// when it has no paths; with paths its Deployed commits are its own, the cell
// carrying the notes of its files.
func (r TbdRow) DeployedCommitsGroups() []spreadGroup {
	if r.PerRepository() && r.DeployPerRepository {
		return []spreadGroup{{State: r.PerRepositorySentence()}}
	}
	deployed := metrics.NotedCell{Value: metrics.GroupDigits(r.DeployedCommits), Notes: r.filesNotes()}
	return []spreadGroup{{Cells: []metrics.NotedCell{deployed}}}
}
