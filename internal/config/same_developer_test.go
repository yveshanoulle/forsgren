package config

import (
	"slices"
	"testing"
)

// TestSameDeveloperReadsGroupsOfLogins (forsgren#361): a list of lists of
// logins is accepted as written, case kept, and the key counts as written.
func TestSameDeveloperReadsGroupsOfLogins(t *testing.T) {
	file := "same_developer:\n  - [maintainer, Assistant-Account]\n  - [other-dev, \"other-bot[bot]\", third_one]\n"
	got, err := parse([]byte(file + valid))
	if err != nil || len(got.Rejected) != 0 {
		t.Fatalf("want nothing rejected and no error, got %v, %v", got.Rejected, err)
	}
	want := [][]string{{"maintainer", "Assistant-Account"}, {"other-dev", "other-bot[bot]", "third_one"}}
	if !slices.EqualFunc(got.SameDeveloper, want, slices.Equal) || !got.written["same_developer"] {
		t.Errorf("want groups %v and the key written, got %v, written %v", want, got.SameDeveloper, got.written)
	}
}

// TestSameDeveloperLeftOutOrEmptyMeansNoGroups (forsgren#361): the key left
// out, written without a value or as an empty list names no group.
func TestSameDeveloperLeftOutOrEmptyMeansNoGroups(t *testing.T) {
	for _, file := range []string{"", "same_developer:\n", "same_developer: []\n"} {
		got, err := parse([]byte(file + valid))
		if !isPlain(got, err) || len(got.Rejected) != 0 {
			t.Errorf("file %q: want no groups and no rejection, got %v, %v, %v", file, got.SameDeveloper, got.Rejected, err)
		}
	}
}

// shape is the reason a same_developer that is not a list of lists gets.
const shape = "use a list of lists of GitHub logins, such as [[maintainer, assistant-account]]"

// TestSameDeveloperRefusalsNameTheKeyAndTheReason (forsgren#361): each
// mistake in the key is rejected with its own reason; no group is applied,
// the default (no groups) is in force, and the key counts as not written.
func TestSameDeveloperRefusalsNameTheKeyAndTheReason(t *testing.T) {
	cases := []struct{ name, file, written, reason string }{
		{"a login in two groups", "same_developer: [[maintainer, helper], [other, helper]]\n",
			"[[maintainer, helper], [other, helper]]", `login "helper" is in group 2 and in group 1 (case is ignored)`},
		{"a login in two groups, other case", "same_developer: [[maintainer, Helper], [other, hELPER]]\n",
			"[[maintainer, Helper], [other, hELPER]]", `login "hELPER" is in group 2 and in group 1 (case is ignored)`},
		{"a login twice in a group", "same_developer: [[maintainer, MAINTAINER]]\n",
			"[[maintainer, MAINTAINER]]", `login "MAINTAINER" is listed twice in group 1 (case is ignored)`},
		{"an empty group", "same_developer: [[maintainer, helper], []]\n",
			"[[maintainer, helper], []]", "group 2 is empty; list two or more logins"},
		{"a group of one", "same_developer: [[maintainer]]\n",
			"[[maintainer]]", `group 1 has one login, "maintainer"; list two or more logins`},
		{"not a login", "same_developer: [[maintainer, not a login]]\n",
			"[[maintainer, not a login]]", `"not a login" in group 1 is not a GitHub login`},
		{"an email address", "same_developer: [[maintainer, a@b.example]]\n",
			"[[maintainer, a@b.example]]", `"a@b.example" in group 1 is not a GitHub login`},
		{"a list of logins", "same_developer: [maintainer, helper]\n", "[maintainer, helper]", shape},
		{"a mapping", "same_developer: {a: b}\n", "{a: b}", shape},
		{"a scalar", "same_developer: maintainer\n", "maintainer", shape},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, err := parse([]byte(c.file + valid))
			if !isPlain(got, err) || got.written["same_developer"] {
				t.Fatalf("want no error, no groups and the key not written, got %v, %v, %v",
					got.SameDeveloper, got.written, err)
			}
			wantRejection(t, got.Rejected, ErrSameDeveloper, [4]string{"same_developer", c.written, c.reason, "[]"})
			if want := `invalid same_developer "` + c.written + `": ` + c.reason; got.Rejected[0].Error() != want {
				t.Errorf("want the message %q, got %q", want, got.Rejected[0].Error())
			}
		})
	}
}

// TestSameDeveloperSettingShowsTheGroupsAsWritten (forsgren#361): the
// settings list the key last, its value the groups in flow form, its default [].
func TestSameDeveloperSettingShowsTheGroupsAsWritten(t *testing.T) {
	got, err := parse([]byte("same_developer: [[maintainer, assistant-account]]\n" + valid))
	if err != nil {
		t.Fatal(err)
	}
	s := got.Settings()
	want := Setting{Key: "same_developer", Value: "[[maintainer, assistant-account]]", Default: "[]", Set: true}
	if last := s[len(s)-3]; last != want {
		t.Errorf("want the last setting %+v, got %+v", want, last)
	}
}

// TestStarterShowsSameDeveloperCommentedOut (forsgren#361): the starter
// explains the key and shows an example line, all comments, so the config the
// starter loads to has no group.
func TestStarterShowsSameDeveloperCommentedOut(t *testing.T) {
	lines := starterLines()
	if !slices.Contains(lines, "#   - [maintainer, assistant-account]") {
		t.Errorf("want the example group commented out in the starter")
	}
	if !slices.Contains(lines, "# same_developer:") {
		t.Errorf("want the line # same_developer: in the starter")
	}
	cfg, err := parse([]byte(Starter))
	if !isPlain(cfg, err) || cfg.written["same_developer"] {
		t.Errorf("want no group and the key not written, got %v, %v", cfg.SameDeveloper, err)
	}
}

// isPlain says whether a load gave no error and no group.
func isPlain(cfg Config, err error) bool { return err == nil && len(cfg.SameDeveloper) == 0 }
