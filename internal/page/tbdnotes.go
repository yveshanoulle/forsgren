package page

import "github.com/yveshanoulle/forsgren/internal/metrics"

// The notes below the TBD table (forsgren#394, step 2, decisions #430 and
// #431): one line for each kind of note that occurs on the page, in the order
// of the numbers, with the projects it applies to and their counts. The cells
// carry the markers; this list says what they mean.

// TbdNoteProject is a project a kind of note applies to, with its count.
type TbdNoteProject struct {
	Name  string
	Count int
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

// notes are the notes of the row's cells: the files' (note 8, forsgren#496)
// first, then the Mainline Lead Time's (forsgren#463, step 9), then the pull
// requests' and the bots' (forsgren#479); the Mainline Interval has none since
// forsgren#588. A project without data (forsgren#394, step 3) has none, a
// project whose pull requests cells are a sentence has none of those, and one
// whose Mainline Lead Time cell is a push state has none of that.
// They are the same whichever figures the table shows (forsgren#423): the mean
// cell has them, or the median cell where it is alone.
func (r TbdRow) notes() []metrics.Note {
	if r.NoData() {
		return nil
	}
	notes := r.filesNotes()
	if r.PushAbsent {
		return notes
	}
	if r.MainLead.State() == "" {
		notes = append(notes, r.MainLead.Notes()...)
	}
	notes = append(notes, leadNotes(r.LeadState(), r.hidden.has(idPRLeadTime), r.Lead)...)
	return append(notes, leadNotes(r.BotLeadState(), r.hidden.has(idBotPRLeadTime), r.BotLead)...)
}

// leadNotes are the notes of a pull request lead time's cells: none while the
// group is a sentence (state) or turned off (forsgren#482).
func leadNotes(state string, hidden bool, m metrics.PRLeadTime) []metrics.Note {
	if state != "" || hidden {
		return nil
	}
	return m.Notes()
}

// TbdNotes are the kinds of note the TBD page's cells have, in the order of
// their numbers; none when no cell has a note.
func (d Data) TbdNotes() []TbdNote {
	rows := d.TbdRows()
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

// projectsWith is the row's project for its notes of kind, once with their
// counts added: the PR Lead Time and the Bot PR Lead Time may both carry one
// (forsgren#479), and the line names the project once.
func projectsWith(kind metrics.NoteKind, row TbdRow) []TbdNoteProject {
	var out []TbdNoteProject
	for _, n := range row.notes() {
		if n.Kind != kind {
			continue
		}
		if len(out) == 0 {
			out = append(out, TbdNoteProject{Name: row.NotesName()})
		}
		out[0].Count += n.Count
	}
	return out
}

// filesNotes are the notes of a service row's Time to deploy and Commits per
// deployment cells: note 8, with the commits left out, while some of its
// commits have no stored files yet (forsgren#496).
func (r TbdRow) filesNotes() []metrics.Note {
	if !r.FilesReading {
		return nil
	}
	return []metrics.Note{{Kind: metrics.NoteFilesReading, Count: r.Deploy.Unread}}
}
