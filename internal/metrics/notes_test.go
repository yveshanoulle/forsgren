package metrics

import (
	"fmt"
	"reflect"
	"slices"
	"testing"
)

// TestNoteKindsKeepTheirNumbersAndTexts (forsgren#394, step 2, Yves's ruling:
// the numbers are fixed forever, the legend uses them too): the seven kinds
// have these numbers and these generic texts; (5) is retired (forsgren#479:
// the Bot PR Lead Time column took its place), its number reserved forever and
// never listed; a new kind appends from (9), and changing a line below is
// changing what (1) to (8) mean on every page.
func TestNoteKindsKeepTheirNumbersAndTexts(t *testing.T) {
	want := map[int]string{
		1: "Mostly estimated: commits timed by author date",
		2: "Commits timed by author date",
		3: "A lower bound: a first commit time of a pull request was cut",
		4: "Pull requests timed by their created time",
		6: "Pushes left out: their commits are not known (incomplete data), not counted as 0",
		7: "History still filling: merge and squash branch commits from before this version are missing",
		8: "Files still being read: commits whose changed files forsgren has not read yet are left out",
	}
	kinds := NoteKinds()
	if len(kinds) != len(want) {
		t.Fatalf("want %d kinds, got %d", len(want), len(kinds))
	}
	for _, k := range kinds {
		wantKind(t, k, k.Number(), want[k.Number()])
	}
	for _, retired := range []NoteKind{5, 9} {
		if retired.Text() != "" || slices.Contains(kinds, retired) {
			t.Errorf("want (%d) no kind with no text, got %q", retired, retired.Text())
		}
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
		"two":  {NotedCell{Notes: []Note{{Kind: NoteLowerBound}, {Kind: NoteUnknownPushes}}}, "tbd-note-3 tbd-note-6"},
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
