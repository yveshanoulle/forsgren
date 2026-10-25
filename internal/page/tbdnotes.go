package page

import "github.com/yveshanoulle/forsgren/internal/metrics"

// The notes below the TBD table (forsgren#394, step 2, decisions #430 and
// #431): one line for each kind of note that occurs on the page, in the order
// of the numbers, with the projects it applies to and their counts. The cells
// carry the markers; this list says what they mean.

// TbdNoteProject is a project a kind of note applies to, with its count and,
// where the note is a part of a whole, the whole (7 of 13 commits).
type TbdNoteProject struct {
	Name  string
	Count int
	Of    int
}

// TbdNote is one kind of note that occurs on the page.
type TbdNote struct {
	Kind     metrics.NoteKind
	Projects []TbdNoteProject
}

// ID is the id of the note's line, which the cells point to.
func (n TbdNote) ID() string { return n.Kind.ID() }

// Number is the note's fixed number.
func (n TbdNote) Number() int { return n.Kind.Number() }

// Text is the note's generic text.
func (n TbdNote) Text() string { return n.Kind.Text() }

// notes are the notes of the row's cells: the Mainline Interval's first, then
// the pull requests'; a project without data (forsgren#394, step 3) has none,
// and a project whose pull requests cells are a sentence has none of those.
// They are the same whichever figures the table shows (forsgren#423): the mean
// cell has them, or the median cell where it is alone.
func (r TbdRow) notes() []metrics.Note {
	if r.NoData() {
		return nil
	}
	notes := append([]metrics.Note{}, r.Interval.MeanCell().Notes...)
	if r.LeadState() != "" {
		return notes
	}
	return append(notes, r.Lead.Notes()...)
}

// TbdNotes are the kinds of note the TBD page's cells have, in the order of
// their numbers; none when no cell has a note.
func (d Data) TbdNotes() []TbdNote {
	rows, err := d.TbdRows()
	if err != nil {
		return nil
	}
	var out []TbdNote
	for _, kind := range metrics.NoteKinds() {
		note := TbdNote{Kind: kind}
		for _, row := range rows {
			note.Projects = append(note.Projects, projectsWith(kind, row)...)
		}
		if len(note.Projects) > 0 {
			out = append(out, note)
		}
	}
	return out
}

// projectsWith is the row's project once for each of its notes of kind.
func projectsWith(kind metrics.NoteKind, row TbdRow) []TbdNoteProject {
	var out []TbdNoteProject
	for _, n := range row.notes() {
		if n.Kind == kind {
			out = append(out, TbdNoteProject{Name: row.Interval.Project, Count: n.Count, Of: n.Of})
		}
	}
	return out
}
