// Package dictionary is the one list of what the generated pages say: every
// number forsgren collects and shows, and every term a reader meets, each with
// a short definition and where it comes from (forsgren#370, decision #371 A).
// The list is dictionary.yml, built into the binary; the Dictionary page
// (dictionary.html, forsgren#370 step 2) is generated from it.
package dictionary

import (
	"cmp"
	_ "embed" // The entries are embedded.
	"errors"
	"fmt"
	"io"
	"regexp"
	"slices"
	"strings"
	"unicode"
	"unicode/utf8"

	"go.yaml.in/yaml/v3"
)

// declared is dictionary.yml, the one text of the dictionary.
//
//go:embed dictionary.yml
var declared string

// Kinds an entry can have.
const (
	// KindNumber is a figure the pages show: a column or a row of numbers.
	KindNumber = "number"
	// KindTerm is a word a reader meets in the pages' text.
	KindTerm = "term"
)

// Entry is one thing the pages show, with its definition.
type Entry struct {
	// Name is the entry's heading on the Dictionary page.
	Name string `yaml:"name"`
	// Kind is KindNumber or KindTerm.
	Kind string `yaml:"kind"`
	// Shown lists the labels the pages use for it when they differ from Name:
	// a number's column heads, a term's spellings. Empty means Name.
	Shown []string `yaml:"shown"`
	// Definition is one short definition.
	Definition string `yaml:"definition"`
	// From says where it comes from: the data file or the window it is
	// counted over.
	From string `yaml:"from"`
}

// Labels are the labels the pages use for the entry: Shown, or Name alone.
func (e Entry) Labels() []string {
	if len(e.Shown) == 0 {
		return []string{e.Name}
	}
	return e.Shown
}

// Anchor is the id of the entry on the Dictionary page, which links point
// to: the name in lower case, each run of other characters than letters and
// digits one hyphen.
func (e Entry) Anchor() string {
	return strings.Trim(nonAlphanumeric.ReplaceAllString(strings.ToLower(e.Name), "-"), "-")
}

// Heading is the name as the Dictionary page heads the entry: its first
// letter in upper case, so a term written in lower case in the pages' text
// still opens its heading like a sentence.
func (e Entry) Heading() string {
	first, size := utf8.DecodeRuneInString(e.Name)
	return string(unicode.ToUpper(first)) + e.Name[size:]
}

// nonAlphanumeric is a run of characters that are neither letters nor digits.
var nonAlphanumeric = regexp.MustCompile(`[^\p{L}\p{N}]+`)

// Section returns the entries of one kind, KindNumber or KindTerm, in
// alphabetical order of their names, ignoring case: the order the Dictionary
// page lists them in.
func Section(kind string) ([]Entry, error) {
	all, err := Entries()
	if err != nil {
		return nil, err
	}
	var section []Entry
	for _, e := range all {
		if e.Kind == kind {
			section = append(section, e)
		}
	}
	slices.SortStableFunc(section, func(a, b Entry) int {
		return cmp.Compare(strings.ToLower(a.Name), strings.ToLower(b.Name))
	})
	return section, nil
}

// Entries returns the dictionary, in the order of dictionary.yml. An entry
// that cannot be read, or is incomplete, or repeats a name, is an error.
func Entries() ([]Entry, error) {
	return parse(declared)
}

// parse is Entries over the entries in text.
func parse(text string) ([]Entry, error) {
	var all []Entry
	dec := yaml.NewDecoder(strings.NewReader(text))
	dec.KnownFields(true)
	if err := dec.Decode(&all); err != nil && !errors.Is(err, io.EOF) {
		return nil, fmt.Errorf("dictionary.yml: %w", err)
	}
	for _, e := range all {
		if err := check(e); err != nil {
			return nil, fmt.Errorf("dictionary.yml: %w", err)
		}
	}
	if err := unique(all); err != nil {
		return nil, fmt.Errorf("dictionary.yml: %w", err)
	}
	return all, nil
}

// check is the error of an incomplete entry.
func check(e Entry) error {
	switch {
	case e.Name == "":
		return errors.New("an entry has no name")
	case e.Kind != KindNumber && e.Kind != KindTerm:
		return fmt.Errorf("%q: kind %q is neither %s nor %s", e.Name, e.Kind, KindNumber, KindTerm)
	case e.Definition == "" || e.From == "":
		return fmt.Errorf("%q: definition and from are both needed", e.Name)
	}
	return nil
}

// unique is the error of a name listed twice, compared ignoring case.
func unique(all []Entry) error {
	seen := map[string]bool{}
	for _, e := range all {
		key := strings.ToLower(e.Name)
		if seen[key] {
			return fmt.Errorf("%q is listed twice", e.Name)
		}
		seen[key] = true
	}
	return nil
}
