// Package dictionary is the one list of what the generated pages say: every
// number forsgren collects and shows, and every term a reader meets, each with
// a short definition and where it comes from (forsgren#370, decision #371 A).
// The list is dictionary.yml, built into the binary; the Dictionary page
// (a later step) is generated from it.
package dictionary

import (
	_ "embed" // The entries are embedded.
	"errors"
	"fmt"
	"io"
	"strings"

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
