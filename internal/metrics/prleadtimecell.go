package metrics

import "time"

// notReadableCell is the cell of a project whose pull request read GitHub
// refused (forsgren#337, step 2).
const notReadableCell = "Pull requests not readable"

// State is the sentence that stands in place of the cells for a project collect
// was refused the pull request read of (forsgren#337, step 2): never a lead
// time of what was read nor anything else; empty for any other project.
func (m PRLeadTime) State() string {
	if m.NotReadable {
		return notReadableCell
	}
	return ""
}

// The TBD page's PR Lead Time cells (forsgren#256, step 2; forsgren#423, Yves
// on #432), of the human pull requests only (forsgren#345, step 2): the mean,
// the median and the 90th percentile, a dash while one is not shown (the median
// below two pull requests, the 90th percentile below ten, all three without a
// human pull request, forsgren#390, step 2). The deviation, the count, the cut
// count and the share merged within 24 hours are not in a cell any more. What
// the cells do not say in words are notes (forsgren#394, step 2): the mean is a
// lower bound with a cut one, the created time stood in for some (decision
// #300), and the bot pull requests are not counted (#341).

// MeanCell is the mean lead time with the notes, which sit on it when the table
// shows all three figures.
func (m PRLeadTime) MeanCell() NotedCell {
	return NotedCell{Value: m.shown(m.HasLeadTime(), m.Mean), Notes: m.Notes()}
}

// MedianCell is the median lead time, a dash below two pull requests.
func (m PRLeadTime) MedianCell() string { return m.shown(m.HasMedian(), m.Median) }

// P90Cell is the 90th percentile of the lead times, a dash below ten pull
// requests.
func (m PRLeadTime) P90Cell() string { return m.shown(m.HasP90(), m.P90) }

// MedianNotedCell is the median lead time with the notes, for the table that
// shows the median alone, where the mean cell is not there to carry them.
func (m PRLeadTime) MedianNotedCell() NotedCell {
	return NotedCell{Value: m.MedianCell(), Notes: m.Notes()}
}

// shown is d written for a cell when there is one, else a dash.
func (m PRLeadTime) shown(has bool, d time.Duration) string {
	if !has {
		return noNumber
	}
	return tbdDuration(d)
}

// Notes are the kinds of note on the cells, with their counts.
func (m PRLeadTime) Notes() []Note {
	var notes []Note
	if m.HasLeadTime() {
		notes = appendNote(notes, NoteLowerBound, m.Cut)
		notes = appendNote(notes, NoteCreatedTime, m.CreatedStandsIn)
	}
	return appendNote(notes, NoteBotsNotCounted, m.Bots)
}
