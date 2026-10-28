package needs

import (
	"strings"
	"testing"
)

// weekly is the refusal of `view: weekly`, as the settings page words it.
var weekly = Refusal{Key: "view", Written: "weekly", Reason: "use standard, numbers or scoring", Default: "standard"}

// TestRefusalItemNamesKeyValueReasonAndDefault (forsgren#538): one item has
// the four facts the settings page shows, in its words.
func TestRefusalItemNamesKeyValueReasonAndDefault(t *testing.T) {
	want := "`view`: `weekly` is not accepted: use standard, numbers or scoring. Using the default `standard`."
	if got := weekly.Item(); got != want {
		t.Errorf("Item: want %q, got %q", want, got)
	}
}

// TestRefusalItemShowsAnEmptyValueAndKeepsOneLine (forsgren#538): an empty
// value reads (empty), as on the settings page, and a value with a backtick or
// a line break cannot leave its code span or break the item's line.
func TestRefusalItemShowsAnEmptyValueAndKeepsOneLine(t *testing.T) {
	empty := Refusal{Key: "view", Reason: "r", Default: "d"}
	if got, want := empty.Item(), "`view`: `(empty)` is not accepted: r. Using the default `d`."; got != want {
		t.Errorf("empty: want %q, got %q", want, got)
	}
	nasty := Refusal{Key: "view", Written: "a`b\nc\r@someone", Reason: "r", Default: "d"}
	got := nasty.Item()
	if strings.ContainsAny(got, "\n\r") || strings.Count(got, "`") != 6 {
		t.Errorf("nasty: want one line with three code spans, got %q", got)
	}
}

// TestBodyHasTheMissingAndTheRefusedUnderTheirOwnHeadings (forsgren#538): the
// missing requirements stand under one heading, the refused settings under
// another, each item under its own; a list that is empty has no heading.
func TestBodyHasTheMissingAndTheRefusedUnderTheirOwnHeadings(t *testing.T) {
	body := Body("1.29.1", []Need{{Steps: "grant it"}}, []Refusal{weekly})
	order := []string{Marker, "## Missing requirements", "- [ ] grant it", "## Refused settings", "- [ ] " + weekly.Item()}
	wantInOrder(t, body, order)
	wantOnlyHeading(t, Body("1.29.1", []Need{{Steps: "grant it"}}, nil), "Missing requirements", "Refused settings")
	wantOnlyHeading(t, Body("1.29.1", nil, []Refusal{weekly}), "Refused settings", "Missing requirements")
}

// wantOnlyHeading fails t unless body has the heading and not the other one.
func wantOnlyHeading(t *testing.T, body, heading, other string) {
	t.Helper()
	if !strings.Contains(body, "## "+heading) || strings.Contains(body, other) {
		t.Errorf("want just the heading %q, got %q", heading, body)
	}
}

// wantInOrder fails t unless each of parts is in body, after the one before.
func wantInOrder(t *testing.T, body string, parts []string) {
	t.Helper()
	at := 0
	for _, part := range parts {
		i := strings.Index(body[at:], part)
		if i < 0 {
			t.Fatalf("want %q after offset %d in order, got %q", part, at, body)
		}
		at += i + len(part)
	}
}
