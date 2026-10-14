package config

import "testing"

// TestAutoUpdateLevelIsRead (forsgren#58): the optional top-level
// auto_update_level key, as written; DefaultLevel when the key is left out, or
// has no value (forsgren#157).
func TestAutoUpdateLevelIsRead(t *testing.T) {
	cases := map[string]string{
		"absent": DefaultLevel,
		"patch":  LevelPatch,
		"minor":  LevelMinor,
		"major":  LevelMajor,
		"null":   DefaultLevel,
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

// TestAutoUpdateWithoutALevelUsesTheDefault (forsgren#157): with auto_update
// on, a level that is absent, or a key with no value, is not refused: the
// level is DefaultLevel, major.
func TestAutoUpdateWithoutALevelUsesTheDefault(t *testing.T) {
	files := map[string]string{
		"absent":   "auto_update: true\n" + valid,
		"no value": "auto_update: true\nauto_update_level:\n" + valid,
	}
	for name, file := range files {
		got, err := parse([]byte(file))
		if err != nil || got.AutoUpdateLevel != DefaultLevel || DefaultLevel != LevelMajor {
			t.Errorf("%s: want level %q and no error, got %q, %v", name, LevelMajor, got.AutoUpdateLevel, err)
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
