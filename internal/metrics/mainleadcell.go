package metrics

// The TBD page's Mainline Lead Time cells (forsgren#463, step 9): the mean,
// the median and the 90th percentile are the Lead spread's own cells
// (DurationSpread.MeanCell and the others), a dash while one is not shown (the
// median below two commits, the p90 below ten). What the cells do not say in
// words are notes: the pushes whose commits are not known and the history
// still filling.

// MeanCell is the mean lead time with the notes, which sit on it when the
// table shows all three figures.
func (m MainlineLeadTime) MeanCell() NotedCell {
	return NotedCell{Value: m.Lead.MeanCell(), Notes: m.Notes()}
}

// MedianNotedCell is the median lead time with the notes, for the table that
// shows the median alone, where the mean cell is not there to carry them.
func (m MainlineLeadTime) MedianNotedCell() NotedCell {
	return NotedCell{Value: m.Lead.MedianCell(), Notes: m.Notes()}
}

// Notes are the kinds of note on the cells: the pushes of the window whose
// commits are unknown, with their count (decision #468), and the history still
// filling (decision #469), which has no count.
func (m MainlineLeadTime) Notes() []Note {
	notes := appendNote(nil, NoteUnknownPushes, m.UnknownPushes)
	if m.Filling {
		notes = append(notes, Note{Kind: NoteFilling})
	}
	return notes
}

// State is PushesNotReadable for a project whose push read was refused,
// PushesNotCollected when no push has been collected, else empty: the same
// words as the push measures', since the lead time is read from the pushes.
func (m MainlineLeadTime) State() string {
	switch {
	case m.NotReadable:
		return PushesNotReadable
	case m.Uncollected:
		return PushesNotCollected
	}
	return ""
}
