package config

import "testing"

// TestViewIsRead (forsgren#46): the optional top-level view key, as
// written; none when the key is left out, or has no value, as for a label.
func TestViewIsRead(t *testing.T) {
	cases := map[string]string{
		"absent":   "",
		"standard": "standard",
		"numbers":  "numbers",
		"null":     "",
	}
	files := map[string]string{
		"absent":   valid,
		"standard": "view: standard\n" + valid,
		"numbers":  valid + "view: numbers\n",
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
// naming the key and the valid values; scoring waits for forsgren#47.
func TestParseRefusesAnInvalidView(t *testing.T) {
	checkRefusals(t, []refusal{
		{"scoring", "view: scoring\n" + valid, ErrView, `invalid view "scoring": use standard or numbers`},
		{"other case", "view: Numbers\n" + valid, ErrView, `invalid view "Numbers": use standard or numbers`},
		{"empty", "view: \"\"\n" + valid, ErrView, `invalid view "": use standard or numbers`},
	})
}
