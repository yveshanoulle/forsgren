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
