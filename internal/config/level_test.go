package config

import "testing"

// TestAutoUpdateLevelIsRead (forsgren#58): the optional top-level
// auto_update_level key, as written; none when the key is left out, or has
// no value, as for the view key.
func TestAutoUpdateLevelIsRead(t *testing.T) {
	cases := map[string]string{
		"absent": "",
		"patch":  LevelPatch,
		"minor":  LevelMinor,
		"major":  LevelMajor,
		"null":   "",
	}
	files := map[string]string{
		"absent": valid,
		"patch":  "auto_update_level: patch\n" + valid,
		"minor":  valid + "auto_update_level: minor\n",
		"major":  "auto_update_level: major\n" + valid,
		"null":   "auto_update_level:\n" + valid,
	}
	for name, want := range cases {
		got, err := parse([]byte(files[name]))
		if err != nil || got.AutoUpdateLevel != want {
			t.Errorf("%s: want level %q and no error, got %q, %v", name, want, got.AutoUpdateLevel, err)
		}
	}
}

// TestParseRefusesAnInvalidAutoUpdateLevel (forsgren#58): any other value is
// refused, naming the key and the valid values, as for an invalid view.
func TestParseRefusesAnInvalidAutoUpdateLevel(t *testing.T) {
	checkRefusals(t, []refusal{
		{"other case", "auto_update_level: Minor\n" + valid, ErrAutoUpdateLevel,
			`invalid auto_update_level "Minor": use patch, minor or major`},
		{"unknown", "auto_update_level: huge\n" + valid, ErrAutoUpdateLevel,
			`invalid auto_update_level "huge": use patch, minor or major`},
		{"number", "auto_update_level: 1\n" + valid, ErrAutoUpdateLevel,
			`invalid auto_update_level "1": use patch, minor or major`},
		{"empty", "auto_update_level: \"\"\n" + valid, ErrAutoUpdateLevel,
			`invalid auto_update_level "": use patch, minor or major`},
	})
}
