package metrics

import (
	"reflect"
	"testing"
	"time"
)

// noHumanPulls is the cell of a project without a human pull request in the
// window, a dash (forsgren#390, step 2).
const noHumanPulls = "-"

// TestMainlineLeadTimeCellShowsMeanCountAndShare (forsgren#256, step 2): the
// cell is the mean, the deviation and the count of pull requests, as the
// Mainline Interval writes them, then the share merged within 24 hours in
// Yves's wording of decision #302 (pull requests, not commits), with the
// counts behind it in brackets (#343, rounded down as before), and a dash for
// the deviation of one; without a human pull request, #342's sentence
// (forsgren#345, step 2).
func TestMainlineLeadTimeCellShowsMeanCountAndShare(t *testing.T) {
	h := time.Hour
	cases := map[string]struct {
		lead MainlineLeadTime
		want string
	}{
		"none": {MainlineLeadTime{}, noHumanPulls},
		"one": {MainlineLeadTime{PullRequests: 1, Mean: 5 * h, WithinReference: 1},
			"5 h ± - · 1 · 100% (1 of 1) pull requests merged within 24 hours of their first commit"},
		"three, two within": {MainlineLeadTime{PullRequests: 3, Mean: 30 * h, Deviation: 2*h + 30*time.Minute,
			WithinReference: 2}, "1 d 6 h ± 2 h 30 · 3 · 66% (2 of 3) pull requests merged within 24 hours of " +
			"their first commit"},
	}
	for name, c := range cases {
		if got := c.lead.Cell().Value; got != c.want {
			t.Errorf("%s: want %q, got %q", name, c.want, got)
		}
	}
}

// TestMainlineLeadTimeCellWritesTheCountWithoutBracketsOfItsOwn (forsgren#394,
// step 2, decision #432, option A): the cut pull requests follow the count in
// brackets, "4 (1 cut)", so a marker after the cell is the only other bracket.
func TestMainlineLeadTimeCellWritesTheCountWithoutBracketsOfItsOwn(t *testing.T) {
	cut := MainlineLeadTime{PullRequests: 4, Mean: 3 * time.Hour, Deviation: time.Hour, WithinReference: 2, Cut: 1}
	want := "3 h ± 1 h · 4 (1 cut) · 50% (2 of 4) pull requests merged within 24 hours of their first commit"
	if got := cut.Cell().Value; got != want {
		t.Errorf("want %q, got %q", want, got)
	}
}

// TestMainlineLeadTimeCellNamesItsNotesAsKinds (forsgren#394, step 2): what
// the cell no longer says in words are notes, each kind with its count, in the
// order of the numbers: the cut ones make the mean a lower bound (3), the
// pull requests the created time stood in for (4), the bot pull requests not
// counted (5), also after a dash; a project not readable has none.
func TestMainlineLeadTimeCellNamesItsNotesAsKinds(t *testing.T) {
	human := MainlineLeadTime{PullRequests: 4, Mean: 3 * time.Hour, Deviation: time.Hour, WithinReference: 2}
	with := func(m MainlineLeadTime, cut, standIn, bots int) MainlineLeadTime {
		m.Cut, m.CreatedStandsIn, m.Bots = cut, standIn, bots
		return m
	}
	cases := map[string]struct {
		lead MainlineLeadTime
		want []Note
	}{
		"none":      {human, nil},
		"cut":       {with(human, 2, 0, 0), []Note{{NoteLowerBound, 2, 0}}},
		"stand-ins": {with(human, 0, 3, 0), []Note{{NoteCreatedTime, 3, 0}}},
		"bots":      {with(human, 0, 0, 1), []Note{{NoteBotsNotCounted, 1, 0}}},
		"all three": {with(human, 1, 2, 3),
			[]Note{{NoteLowerBound, 1, 0}, {NoteCreatedTime, 2, 0}, {NoteBotsNotCounted, 3, 0}}},
		"no human, bots": {with(MainlineLeadTime{}, 0, 0, 3), []Note{{NoteBotsNotCounted, 3, 0}}},
		"no human, none": {MainlineLeadTime{}, nil},
		"not readable":   {with(MainlineLeadTime{NotReadable: true}, 0, 0, 2), nil},
	}
	for name, c := range cases {
		if got := c.lead.Cell().Notes; !reflect.DeepEqual(got, c.want) {
			t.Errorf("%s: want the notes %v, got %v", name, c.want, got)
		}
	}
}

// TestMainlineLeadTimeCellValueHasNoNoteSentence (forsgren#394, step 2): the
// value of a cell with every note is the counted part alone, never a sentence
// of a note; after a dash it is the dash; not readable is its own sentence.
func TestMainlineLeadTimeCellValueHasNoNoteSentence(t *testing.T) {
	const counted = "3 h ± - · 1 · 100% (1 of 1) pull requests merged within 24 hours of their first commit"
	human := MainlineLeadTime{PullRequests: 1, Mean: 3 * time.Hour, WithinReference: 1, CreatedStandsIn: 1, Bots: 2}
	cases := map[string]struct {
		lead MainlineLeadTime
		want string
	}{
		"human, notes":   {human, counted},
		"no human, bots": {MainlineLeadTime{Bots: 3}, noHumanPulls},
		"not readable":   {MainlineLeadTime{NotReadable: true, Bots: 2}, "Pull requests not readable"},
	}
	for name, c := range cases {
		if got := c.lead.Cell().Value; got != c.want {
			t.Errorf("%s: want %q, got %q", name, c.want, got)
		}
	}
}
