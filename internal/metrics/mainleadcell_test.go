package metrics

import (
	"reflect"
	"testing"
	"time"
)

// The Mainline Lead Time's cells on the TBD page (forsgren#463, step 9).

// leadCells is a Mainline Lead Time of 12 commits, 2 pushes of unknown
// commits and a history still filling.
func leadCells() MainlineLeadTime {
	return MainlineLeadTime{Project: "Acme Shop", Commits: 12, UnknownPushes: 2, Filling: true,
		Lead: DurationSpread{Count: 12, Mean: 4 * time.Hour, Median: 3 * time.Hour, P90: 9 * time.Hour}}
}

// TestMainlineLeadTimeCellsCarryTheNotesOnTheMeanOrTheMedianAlone: the notes
// sit on the mean cell, or on the median cell where it is alone.
func TestMainlineLeadTimeCellsCarryTheNotesOnTheMeanOrTheMedianAlone(t *testing.T) {
	m := leadCells()
	notes := []Note{{Kind: NoteUnknownPushes, Count: 2}, {Kind: NoteFilling}}
	if got := m.MeanCell(); got.Value != "4 h" || !reflect.DeepEqual(got.Notes, notes) {
		t.Errorf("want 4 h with %v, got %+v", notes, got)
	}
	if got := m.MedianNotedCell(); got.Value != "3 h" || !reflect.DeepEqual(got.Notes, notes) {
		t.Errorf("want 3 h with %v, got %+v", notes, got)
	}
}

// TestMainlineLeadTimeHasNoNoteWhenNothingIsMissing: no unknown push, no
// filling, no note; Filling alone is note 7 without a count.
func TestMainlineLeadTimeHasNoNoteWhenNothingIsMissing(t *testing.T) {
	m := leadCells()
	m.UnknownPushes, m.Filling = 0, false
	if got := m.Notes(); got != nil {
		t.Errorf("want no note, got %v", got)
	}
	m.Filling = true
	if got := m.Notes(); !reflect.DeepEqual(got, []Note{{Kind: NoteFilling}}) {
		t.Errorf("want note 7 alone, got %v", got)
	}
}

// TestMainlineLeadTimeStateIsThePushStateWords: a refused push read and an
// uncollected push file are the words Time to main uses, and nothing else.
func TestMainlineLeadTimeStateIsThePushStateWords(t *testing.T) {
	got := [3]string{MainlineLeadTime{NotReadable: true}.State(), MainlineLeadTime{Uncollected: true}.State(),
		leadCells().State()}
	if want := [3]string{PushesNotReadable, PushesNotCollected, ""}; got != want {
		t.Errorf("want %q, got %q", want, got)
	}
}
