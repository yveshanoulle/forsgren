package config

import "testing"

// TestAutoUpdateIsRead (forsgren#58): the optional top-level auto_update
// key, as written; off when the key is left out.
func TestAutoUpdateIsRead(t *testing.T) {
	cases := map[string]bool{
		"absent": false,
		"off":    false,
		"on":     true,
	}
	files := map[string]string{
		"absent": valid,
		"off":    "auto_update: false\n" + valid,
		"on":     valid + "auto_update: true\n",
	}
	for name, want := range cases {
		got, err := parse([]byte(files[name]))
		if err != nil || got.AutoUpdate != want {
			t.Errorf("%s: want auto_update %v and no error, got %v, %v", name, want, got.AutoUpdate, err)
		}
	}
}

// TestParseRefusesANonBooleanAutoUpdate (forsgren#58): any value that is not
// the YAML boolean true or false is refused, naming the key and the valid
// values, as for an invalid view.
func TestParseRefusesANonBooleanAutoUpdate(t *testing.T) {
	checkRefusals(t, []refusal{
		{"yes", "auto_update: yes\n" + valid, ErrAutoUpdate, `invalid auto_update "yes": use true or false`},
		{"quoted", "auto_update: \"true\"\n" + valid, ErrAutoUpdate, `invalid auto_update "true": use true or false`},
		{"number", "auto_update: 1\n" + valid, ErrAutoUpdate, `invalid auto_update "1": use true or false`},
	})
}
