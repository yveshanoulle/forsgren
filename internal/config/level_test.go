package config

import (
	"strconv"
	"testing"
)

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

// TestRejectedAutoUpdateLevelFallsBackToMajor (forsgren#58, #183): any other
// value is not accepted: the level is DefaultLevel and not written, auto_update
// keeps its own value, and the rejection names the key and the valid values.
func TestRejectedAutoUpdateLevelFallsBackToMajor(t *testing.T) {
	for _, written := range []string{"Minor", "huge", "1", ""} {
		t.Run(written, func(t *testing.T) {
			got, err := parse([]byte("auto_update: true\nauto_update_level: " + strconv.Quote(written) + "\n" + valid))
			if err != nil || !got.AutoUpdate || got.AutoUpdateLevel != DefaultLevel || got.written["auto_update_level"] {
				t.Fatalf("want auto_update on, level %q not written and no error, got %v, %q, %v, %v",
					DefaultLevel, got.AutoUpdate, got.AutoUpdateLevel, got.written, err)
			}
			wantRejection(t, got.Rejected, ErrAutoUpdateLevel,
				[4]string{"auto_update_level", written, "use patch, minor or major", DefaultLevel})
		})
	}
}
