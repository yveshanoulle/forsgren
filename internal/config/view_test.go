package config

import "testing"

// TestViewIsRead (forsgren#46): the optional top-level view key, as
// written; none when the key is left out, or has no value, as for a label.
func TestViewIsRead(t *testing.T) {
	cases := map[string]string{
		"absent":   "",
		"standard": "standard",
		"numbers":  "numbers",
		"scoring":  "scoring",
		"null":     "",
	}
	files := map[string]string{
		"absent":   valid,
		"standard": "view: standard\n" + valid,
		"numbers":  valid + "view: numbers\n",
		"scoring":  "view: scoring\n" + valid,
		"null":     "view:\n" + valid,
	}
	for name, want := range cases {
		got, err := parse([]byte(files[name]))
		if err != nil || got.View != want {
			t.Errorf("%s: want view %q and no error, got %q, %v", name, want, got.View, err)
		}
	}
}

// TestParseRefusesAnInvalidView (forsgren#46): any other value is refused,
// naming the key and the valid values.
func TestParseRefusesAnInvalidView(t *testing.T) {
	checkRefusals(t, []refusal{
		{"other case", "view: Numbers\n" + valid, ErrView, `invalid view "Numbers": use standard, numbers or scoring`},
		{"empty", "view: \"\"\n" + valid, ErrView, `invalid view "": use standard, numbers or scoring`},
	})
}
