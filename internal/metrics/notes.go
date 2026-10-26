package metrics

// The notes of the TBD page's cells (forsgren#394, step 2): each kind of
// note has a number that is fixed forever (Yves's ruling on #394), so (1) means
// the same on every page and in the legend, and a generic text that says what
// the kind claims, without a count. A cell returns its value and the kinds of
// note that apply to it, each with the count behind it; the page writes the
// markers in the cell and the list of the kinds that occur below the table.
// A new kind appends at the next number; no number is reused or reordered.

import "fmt"

// NoteKind is the number of one kind of note, 1 to 7 today, 5 retired.
type NoteKind int

// The kinds of note, by their fixed numbers.
const (
	// NoteMostlyEstimated: more than half of the commits of an interval are
	// timed by author date.
	NoteMostlyEstimated NoteKind = 1
	// NoteByAuthorDate: some, at most half, of the commits are.
	NoteByAuthorDate NoteKind = 2
	// NoteLowerBound: a pull request's first commit time was cut, so the mean
	// is a lower bound.
	NoteLowerBound NoteKind = 3
	// NoteCreatedTime: the created time of pull requests stands in for a
	// first commit time.
	NoteCreatedTime NoteKind = 4
	// Number 5 is retired (forsgren#479: the Bot PR Lead Time column took the
	// place of "Bot pull requests not counted"): its number stays reserved
	// forever, no cell shows it and the Notes list never lists it.
	// NoteUnknownPushes: pushes of the window whose commits are not known (a
	// cut or failed compare, a force push) are left out of the Mainline Lead
	// Time (forsgren#463, decision #468).
	NoteUnknownPushes NoteKind = 6
	// NoteFilling: the window holds data from before the commits of merges and
	// squashes were stored, so the Mainline Lead Time may be short
	// (forsgren#463, decision #469).
	NoteFilling NoteKind = 7
)

// noteTexts is the one table of the kinds and their generic texts, in the
// order of their numbers; TestNoteKindsKeepTheirNumbersAndTexts pins it.
var noteTexts = []struct {
	kind NoteKind
	text string
}{
	{NoteMostlyEstimated, "Mostly estimated: commits timed by author date"},
	{NoteByAuthorDate, "Commits timed by author date"},
	{NoteLowerBound, "A lower bound: a first commit time of a pull request was cut"},
	{NoteCreatedTime, "Pull requests timed by their created time"},
	{NoteUnknownPushes, "Pushes left out: their commits are not known (incomplete data), not counted as 0"},
	{NoteFilling, "History still filling: merge and squash branch commits from before this version are missing"},
}

// NoteKinds are all the kinds, in the order of their numbers.
func NoteKinds() []NoteKind {
	kinds := make([]NoteKind, len(noteTexts))
	for i, row := range noteTexts {
		kinds[i] = row.kind
	}
	return kinds
}

// Number is the kind's fixed number, 1 for NoteMostlyEstimated.
func (k NoteKind) Number() int { return int(k) }

// ID is the id of the kind's line below the TBD table, "tbd-note-1", which a
// cell points to with aria-describedby.
func (k NoteKind) ID() string { return fmt.Sprintf("tbd-note-%d", int(k)) }

// Text is the kind's generic text; empty for a number that is no kind.
func (k NoteKind) Text() string {
	for _, row := range noteTexts {
		if row.kind == k {
			return row.text
		}
	}
	return ""
}

// Note is one kind of note that applies to a cell, with the count behind it
// and, for the commits timed by author date, the commits they are among.
type Note struct {
	Kind  NoteKind
	Count int
	// Of is the whole Count is part of, or 0 when the note has none.
	Of int
}

// Number is the note's kind number, for the marker.
func (n Note) Number() int { return n.Kind.Number() }

// NotedCell is a cell's value and the notes that apply to it.
type NotedCell struct {
	Value string
	Notes []Note
}

// DescribedBy are the ids of the cell's notes, parted by a space, for
// aria-describedby; empty without a note.
func (c NotedCell) DescribedBy() string {
	ids := ""
	for i, n := range c.Notes {
		if i > 0 {
			ids += " "
		}
		ids += n.Kind.ID()
	}
	return ids
}

// appendNote adds a note of kind for count items (pull requests, pushes)
// when there are any.
func appendNote(notes []Note, kind NoteKind, count int) []Note {
	if count == 0 {
		return notes
	}
	return append(notes, Note{Kind: kind, Count: count})
}
