package dictionary

import (
	"fmt"
	"strings"
	"testing"
)

func TestAnchorIsTheNameAsALowerCaseSlug(t *testing.T) {
	cases := map[string]string{
		"Deployment frequency": "deployment-frequency",
		"Open / Total":         "open-total",
		"stand-in":             "stand-in",
		"p90":                  "p90",
		" Calculated at ":      "calculated-at",
	}
	for name, want := range cases {
		if got := (Entry{Name: name}).Anchor(); got != want {
			t.Errorf("Anchor of %q = %q, want %q", name, got, want)
		}
	}
}

func TestHeadingOpensTheNameWithACapital(t *testing.T) {
	cases := map[string]string{"trunk": "Trunk", "Quick Check": "Quick Check", "p90": "P90", "élan": "Élan"}
	for name, want := range cases {
		if got := (Entry{Name: name}).Heading(); got != want {
			t.Errorf("Heading of %q = %q, want %q", name, got, want)
		}
	}
}

func TestEveryEntryHasItsOwnAnchor(t *testing.T) {
	seen := map[string]string{}
	for _, e := range entries(t) {
		anchor := e.Anchor()
		if anchor == "" {
			t.Errorf("%q has no anchor", e.Name)
		}
		if other, ok := seen[anchor]; ok {
			t.Errorf("%q and %q share the anchor %q", other, e.Name, anchor)
		}
		seen[anchor] = e.Name
	}
}

func TestSectionListsOneKindAlphabetically(t *testing.T) {
	for _, kind := range []string{KindNumber, KindTerm} {
		got, err := Section(kind)
		if err != nil || len(got) == 0 {
			t.Fatalf("Section(%s) = %d entries, %v; want some", kind, len(got), err)
		}
		for i := range got {
			if problem := misplaced(got, i, kind); problem != "" {
				t.Errorf("Section(%s): %s", kind, problem)
			}
		}
	}
}

// misplaced says what is wrong with the entry at i of a section of kind: its
// kind, or its place after the entry before it.
func misplaced(section []Entry, i int, kind string) string {
	e := section[i]
	if e.Kind != kind {
		return fmt.Sprintf("holds %s %q", e.Kind, e.Name)
	}
	if i > 0 && !alphabetical(section[i-1], e) {
		return fmt.Sprintf("%q comes before %q", section[i-1].Name, e.Name)
	}
	return ""
}

// alphabetical says whether a may come before b, ignoring case.
func alphabetical(a, b Entry) bool { return strings.ToLower(a.Name) <= strings.ToLower(b.Name) }

func TestSectionsHoldEveryEntryOnce(t *testing.T) {
	numbers, _ := Section(KindNumber)
	terms, _ := Section(KindTerm)
	if want := len(entries(t)); len(numbers)+len(terms) != want {
		t.Errorf("the sections hold %d entries, the dictionary has %d", len(numbers)+len(terms), want)
	}
}
