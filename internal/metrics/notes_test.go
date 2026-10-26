package metrics

import (
	"fmt"
	"reflect"
	"testing"
)

// TestNoteKindsKeepTheirNumbersAndTexts (forsgren#394, step 2, Yves's ruling:
// the numbers are fixed forever, the legend uses them too): the seven kinds
// have these numbers and these generic texts; a new kind appends from (8), and
// changing a line below is changing what (1) to (7) mean on every page.
func TestNoteKindsKeepTheirNumbersAndTexts(t *testing.T) {
	want := map[int]string{
		1: "Mostly estimated: commits timed by author date",
		2: "Commits timed by author date",
		3: "A lower bound: a first commit time of a pull request was cut",
		4: "Pull requests timed by their created time",
		5: "Bot pull requests not counted",
		6: "Pushes left out: their commits are not known (incomplete data), not counted as 0",
		7: "History still filling: merge and squash branch commits from before this version are missing",
	}
	kinds := NoteKinds()
	if len(kinds) != len(want) {
		t.Fatalf("want %d kinds, got %d", len(want), len(kinds))
	}
	for i, k := range kinds {
		wantKind(t, k, i+1, want[i+1])
	}
	if (NoteKind(8)).Text() != "" {
		t.Errorf("want no text for a number that is no kind, got %q", NoteKind(8).Text())
	}
}

// wantKind holds k to its number, its generic text and its id.
func wantKind(t *testing.T, k NoteKind, number int, text string) {
	t.Helper()
	if k.Number() != number || k.Text() != text {
		t.Errorf("kind %d: want (%d) %q, got (%d) %q", number, number, text, k.Number(), k.Text())
	}
	if id, want := k.ID(), fmt.Sprintf("tbd-note-%d", number); id != want {
		t.Errorf("kind %d: want the id %s, got %q", number, want, id)
	}
}

// TestNotedCellDescribedByNamesEachNote (forsgren#394, step 2): the cell
// points at the line of each of its notes, parted by a space, and at none
// without a note.
func TestNotedCellDescribedByNamesEachNote(t *testing.T) {
	cases := map[string]struct {
		cell NotedCell
		want string
	}{
		"none": {NotedCell{Value: "-"}, ""},
		"one":  {NotedCell{Notes: []Note{{Kind: NoteByAuthorDate}}}, "tbd-note-2"},
		"two":  {NotedCell{Notes: []Note{{Kind: NoteLowerBound}, {Kind: NoteBotsNotCounted}}}, "tbd-note-3 tbd-note-5"},
	}
	for name, c := range cases {
		if got := c.cell.DescribedBy(); got != c.want {
			t.Errorf("%s: want %q, got %q", name, c.want, got)
		}
	}
	if n := (Note{Kind: NoteCreatedTime, Count: 2}); n.Number() != 4 || !reflect.DeepEqual(n, Note{4, 2, 0}) {
		t.Errorf("want number 4, got %d", n.Number())
	}
}
