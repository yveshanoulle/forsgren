package config

import (
	"errors"
	"strconv"
	"testing"
)

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

// TestRejectedViewFallsBackToTheDefault (forsgren#183): a view that is not
// accepted no longer stops the load: the view is none, as when the key is
// left out and not written, and the rejection names the key, the value as
// written, the reason and the default in use. Its message is the old
// refusal's, and it unwraps to ErrView.
func TestRejectedViewFallsBackToTheDefault(t *testing.T) {
	cases := []struct{ name, yaml, written string }{
		{"other case", "view: Numbers\n" + valid, "Numbers"},
		{"empty", "view: \"\"\n" + valid, ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := parse([]byte(tc.yaml))
			if err != nil || got.View != "" || got.written["view"] {
				t.Fatalf("want no error, no view and view not written, got %q, %v, %v", got.View, got.written, err)
			}
			wantRejection(t, got.Rejected, ErrView,
				[4]string{"view", tc.written, "use standard, numbers or scoring", ViewStandard})
		})
	}
}

// wantRejection wants exactly one rejection, with the key, value as written,
// reason and default of want, whose message is the old refusal's and unwraps
// to sentinel.
func wantRejection(t *testing.T, rejected []Rejection, sentinel error, want [4]string) {
	t.Helper()
	if len(rejected) != 1 {
		t.Fatalf("want one rejection, got %v", rejected)
	}
	r := rejected[0]
	if have := [4]string{r.Key, r.Written, r.Reason, r.Default}; have != want {
		t.Errorf("want rejection %q, got %q", want, have)
	}
	message := "invalid " + want[0] + " " + strconv.Quote(want[1]) + ": " + want[2]
	if r.Error() != message || !errors.Is(&r, sentinel) {
		t.Errorf("want message %q unwrapping to %v, got %q", message, sentinel, r.Error())
	}
}

// TestRejectedViewDoesNotHideAFileError (forsgren#183): a setting with a
// default falls back, but a file error still stops the load.
func TestRejectedViewDoesNotHideAFileError(t *testing.T) {
	_, err := parse([]byte("version: 1\nview: Numbers\n"))
	wantRefusal(t, err, ErrNoProjects)
}
