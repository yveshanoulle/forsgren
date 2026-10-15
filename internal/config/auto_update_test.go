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
		"on":     valid + "auto_update: true\nauto_update_level: patch\n",
	}
	for name, want := range cases {
		got, err := parse([]byte(files[name]))
		if err != nil || got.AutoUpdate != want {
			t.Errorf("%s: want auto_update %v and no error, got %v, %v", name, want, got.AutoUpdate, err)
		}
	}
}

// TestAutoUpdateWithNoValueIsOff (forsgren#58): a key with no value, null or
// ~ is none, as for the view key: off, and no error.
func TestAutoUpdateWithNoValueIsOff(t *testing.T) {
	keys := map[string]string{
		"empty": "auto_update:\n",
		"null":  "auto_update: null\n",
		"tilde": "auto_update: ~\n",
	}
	for name, key := range keys {
		got, err := parse([]byte(key + valid))
		if err != nil || got.AutoUpdate {
			t.Errorf("%s: want auto_update off and no error, got %v, %v", name, got.AutoUpdate, err)
		}
	}
}

// TestRejectedAutoUpdateFallsBackToOff (forsgren#58, #183): any value that is
// not the YAML boolean true or false is not accepted: auto_update is off, as
// when the key is left out and not written, and the rejection names the key.
func TestRejectedAutoUpdateFallsBackToOff(t *testing.T) {
	for written, yaml := range map[string]string{"yes": "yes", "true": `"true"`, "1": "1"} {
		t.Run(written, func(t *testing.T) {
			got, err := parse([]byte("auto_update: " + yaml + "\n" + valid))
			if err != nil || got.AutoUpdate || got.written["auto_update"] {
				t.Fatalf("want no error, auto_update off and not written, got %v, %v, %v",
					got.AutoUpdate, got.written, err)
			}
			wantRejection(t, got.Rejected, ErrAutoUpdate, [4]string{"auto_update", written, "use true or false", "false"})
		})
	}
}
