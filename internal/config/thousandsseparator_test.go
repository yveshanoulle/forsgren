package config

import "testing"

// TestThousandsSeparatorAcceptsItsThreeValues (forsgren#528): narrow_space, comma
// and none are accepted as written; a file without the key has the default,
// narrow_space, and the key is not written.
func TestThousandsSeparatorAcceptsItsThreeValues(t *testing.T) {
	for file, want := range map[string]string{"": "narrow_space", "thousands_separator:\n": "narrow_space",
		"thousands_separator: narrow_space\n": "narrow_space", "thousands_separator: comma\n": "comma",
		"thousands_separator: none\n": "none"} {
		got, err := parse([]byte(file + valid))
		if err != nil || got.ThousandsSeparator != want || len(got.Rejected) != 0 {
			t.Errorf("file %q: want %q and no rejection, got %q, %v, %v", file, want, got.ThousandsSeparator, got.Rejected, err)
		}
	}
}

// TestThousandsSeparatorRefusesAPeriod (forsgren#528): a period is not a value,
// the pages keep the decimal point; the Rejection names the three values and
// the default stays in force.
func TestThousandsSeparatorRefusesAPeriod(t *testing.T) {
	got, err := parse([]byte("thousands_separator: period\n" + valid))
	if err != nil || got.ThousandsSeparator != "narrow_space" {
		t.Fatalf("want the default in force and no error, got %q, %v", got.ThousandsSeparator, err)
	}
	wantRejection(t, got.Rejected, ErrThousandsSeparator,
		[4]string{"thousands_separator", "period", "use narrow_space, comma or none", "narrow_space"})
}
