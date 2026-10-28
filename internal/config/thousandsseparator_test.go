package config

import "testing"

// TestThousandsSeparatorAcceptsItsFourValues (forsgren#528, #536): narrow_space,
// comma, period (beside a decimal comma) and none are accepted as written; a file without the key has the default,
// narrow_space, and the key is not written.
func TestThousandsSeparatorAcceptsItsFourValues(t *testing.T) {
	for file, want := range map[string]string{"": "narrow_space", "thousands_separator:\n": "narrow_space",
		"thousands_separator: narrow_space\n": "narrow_space", "thousands_separator: comma\n": "comma",
		"thousands_separator: none\n": "none", "thousands_separator: period\ndecimal_separator: comma\n": "period"} {
		got, err := parse([]byte(file + valid))
		if err != nil || got.ThousandsSeparator != want || len(got.Rejected) != 0 {
			t.Errorf("file %q: want %q and no rejection, got %q, %v, %v", file, want, got.ThousandsSeparator, got.Rejected, err)
		}
	}
}

// TestThousandsSeparatorRefusesAnUnknownValue (forsgren#528, #536): a value
// that is none of the four is a Rejection naming them, the default stays in
// force.
func TestThousandsSeparatorRefusesAnUnknownValue(t *testing.T) {
	got, err := parse([]byte("thousands_separator: dot\n" + valid))
	if err != nil || got.ThousandsSeparator != "narrow_space" {
		t.Fatalf("want the default in force and no error, got %q, %v", got.ThousandsSeparator, err)
	}
	wantRejection(t, got.Rejected, ErrThousandsSeparator,
		[4]string{"thousands_separator", "dot", "use narrow_space, comma, period or none", "narrow_space"})
}
