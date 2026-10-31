package page

import "testing"

// TestTbdPageListsTheNotesThatOccurBelowTheTable (forsgren#394, step 2,
// decisions #430 and #431): below the table a details element, summary Notes,
// open by default, lists one line per kind of note that occurs, in the order of
// the numbers, each with the id its cells point to, the generic text and the
// projects it applies to with their counts.
func TestTbdPageListsTheNotesThatOccurBelowTheTable(t *testing.T) {
	got := rendered(t, "tbd.html", tbdData())
	const open = "</table>\n    </div>\n    <details class=\"tbd-notes\" open>\n" +
		"      <summary>Notes</summary>\n      <ul>\n"
	const end = "      </ul>\n    </details>\n"
	list := "        <li id=\"tbd-note-3\">(3) A lower bound: a first commit time of a pull request was cut: " +
		"Acme Tools 2</li>\n" +
		"        <li id=\"tbd-note-4\">(4) Pull requests timed by their created time: " +
		"Acme Tools 1, Acme Web 1</li>\n" +
		"        <li id=\"tbd-note-6\">(6) Pushes left out: their commits are not known (incomplete data), " +
		"not counted as 0: Acme Shop 2</li>\n" +
		"        <li id=\"tbd-note-7\">(7) History still filling: merge and squash branch commits from before " +
		"this version are missing: Acme Shop</li>\n"
	wantAll(t, "tbd.html", got, open+list+end)
}

// TestTbdPageListsTheMainlineLeadTimeNotesOnlyWhileTheyApply (forsgren#463,
// step 9, decisions #468 and #469): note 6 names the project and its count of
// pushes left out, note 7 the project while its history fills and no count;
// both are gone with nothing unknown and a history that is filled, and a state
// cell notes neither.
func TestTbdPageListsTheMainlineLeadTimeNotesOnlyWhileTheyApply(t *testing.T) {
	data := tbdData()
	data.TbdMetrics[0].MainLead.Filling = false
	got := rendered(t, "tbd.html", data)
	wantAll(t, "filled", got, `id="tbd-note-6"`)
	wantNone(t, "filled", got, `id="tbd-note-7"`, "Acme Docs 1")
	data.TbdMetrics[0].MainLead.UnknownPushes = 0
	wantNone(t, "none unknown", rendered(t, "tbd.html", data), `id="tbd-note-6"`, `id="tbd-note-7"`)
}

// TestTbdPageListsOnlyTheKindsThatOccur(forsgren#394, step 2): without any
// note there is no Notes element at all, and a kind that no cell has is not
// listed.
func TestTbdPageListsOnlyTheKindsThatOccur(t *testing.T) {
	none := noPulls()
	for i := range none.TbdMetrics {
		none.TbdMetrics[i].MainLead.UnknownPushes, none.TbdMetrics[i].MainLead.Filling = 0, false
	}
	wantNone(t, "no note", rendered(t, "tbd.html", none), "<details", "Notes", "tbd-note-", "visually-hidden")
	partial := noPulls()
	partial.TbdMetrics[0].MainLead.Filling = false
	got := rendered(t, "tbd.html", partial)
	wantAll(t, "kind 6 stays", got, `id="tbd-note-6"`)
	wantNone(t, "kind 7 gone", got, `id="tbd-note-7"`, `id="tbd-note-3"`)
}
