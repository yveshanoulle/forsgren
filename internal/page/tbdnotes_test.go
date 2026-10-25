package page

import "testing"

// TestTbdPageListsTheNotesThatOccurBelowTheTable (forsgren#394, step 2,
// decisions #430 and #431): below the table a details element, summary Notes,
// open by default, lists one line per kind of note that occurs, in the order of
// the numbers, each with the id its cells point to, the generic text and the
// projects it applies to with their counts; "7 of 13" where the note is a part
// of a whole.
func TestTbdPageListsTheNotesThatOccurBelowTheTable(t *testing.T) {
	got := rendered(t, "tbd.html", tbdData())
	const open = "</table>\n    </div>\n    <details class=\"tbd-notes\" open>\n" +
		"      <summary>Notes</summary>\n      <ul>\n"
	const end = "      </ul>\n    </details>\n"
	list := "        <li id=\"tbd-note-1\">(1) Mostly estimated: commits timed by author date: Acme Web 7 of 13</li>\n" +
		"        <li id=\"tbd-note-2\">(2) Commits timed by author date: Acme Shop 2</li>\n" +
		"        <li id=\"tbd-note-3\">(3) A lower bound: a first commit time of a pull request was cut: " +
		"Acme Tools 1</li>\n" +
		"        <li id=\"tbd-note-4\">(4) Pull requests timed by their created time: Acme Web 1</li>\n" +
		"        <li id=\"tbd-note-5\">(5) Bot pull requests not counted: Acme Docs 2, Acme Web 3</li>\n"
	wantAll(t, "tbd.html", got, open+list+end)
}

// TestTbdPageListsOnlyTheKindsThatOccur (forsgren#394, step 2): without any
// note there is no Notes element at all, and a kind that no cell has is not
// listed.
func TestTbdPageListsOnlyTheKindsThatOccur(t *testing.T) {
	none := tbdDataWith(noLeads())
	for i := range none.Mainline {
		none.Mainline[i].ByAuthorDate = 0
	}
	wantNone(t, "no note", rendered(t, "tbd.html", none), "<details", "Notes", "tbd-note-", "visually-hidden")
	partial := tbdDataWith(noLeads())
	partial.Mainline[3].ByAuthorDate = 0
	got := rendered(t, "tbd.html", partial)
	wantAll(t, "kind 2 stays", got, `id="tbd-note-2"`)
	wantNone(t, "kind 1 gone", got, `id="tbd-note-1"`, `id="tbd-note-3"`)
}

// TestTbdNotesAreNoneWhereTheRowsDoNotPair (forsgren#394, step 2): measures of
// other projects fail the render; asked for directly, the notes are none, never
// a note in the wrong row.
func TestTbdNotesAreNoneWhereTheRowsDoNotPair(t *testing.T) {
	data := tbdData()
	data.MainlineLead = data.MainlineLead[:3]
	if got := data.TbdNotes(); got != nil {
		t.Errorf("want no notes, got %v", got)
	}
}
