package config

import (
	"slices"
	"strings"
	"testing"
)

// TestSettingsListsEveryKeyWithItsDefault (forsgren#74): a file that writes
// only history_days has that key Set with its value, every other key unset
// with its default, in the fixed order.
func TestSettingsListsEveryKeyWithItsDefault(t *testing.T) {
	wantSettings(t, "history_days: 30\n", []Setting{
		{Key: "view", Value: "standard", Default: "standard"},
		{Key: "sub_rows", Value: "true", Default: "true"},
		{Key: "auto_update", Value: "false", Default: "false"},
		{Key: "auto_update_level", Value: "major", Default: "major"},
		{Key: "history_days", Value: "30", Default: "365", Set: true},
		{Key: "history_chunk_days", Value: "100", Default: "100"},
		{Key: "working_hours", Value: "8", Default: "8"},
		{Key: "dora_days", Value: "30", Default: "30"},
		{Key: "issues_page", Value: "true", Default: "true"},
		{Key: "days_page", Value: "false", Default: "false"},
		{Key: "numbers_scoring_page", Value: "unlisted", Default: "unlisted"},
		{Key: "history_page", Value: "unlisted", Default: "unlisted"},
		{Key: "tbd_page", Value: "true", Default: "true"},
		{Key: "week_page", Value: "true", Default: "true"},
		{Key: "tbd_figures", Value: "median", Default: "median"},
		{Key: "tbd_time_to_main", Value: "true", Default: "true"},
		{Key: "tbd_pr_lead_time", Value: "true", Default: "true"},
		{Key: "tbd_bot_pr_lead_time", Value: "true", Default: "true"},
		{Key: "same_developer", Value: "[]", Default: "[]"},
		{Key: "thousands_separator", Value: "narrow_space", Default: "narrow_space"},
	})
}

// TestSettingsMarksEveryWrittenKeySet (forsgren#74): a file that writes all
// twenty keys has all of them Set, with the written values.
func TestSettingsMarksEveryWrittenKeySet(t *testing.T) {
	all := "view: numbers\nauto_update: true\nauto_update_level: minor\n" +
		"history_days: 30\nhistory_chunk_days: 10\nworking_hours: 6\ndora_days: 30\nissues_page: false\ndays_page: true\n" +
		"numbers_scoring_page: true\nhistory_page: false\ntbd_page: true\nweek_page: false\ntbd_figures: all\n" +
		"tbd_time_to_main: false\ntbd_pr_lead_time: false\ntbd_bot_pr_lead_time: false\nsub_rows: false\n" +
		"same_developer: [[maintainer, assistant-account]]\nthousands_separator: comma\n"
	wantSettings(t, all, []Setting{
		{Key: "view", Value: "numbers", Default: "standard", Set: true},
		{Key: "sub_rows", Value: "false", Default: "true", Set: true},
		{Key: "auto_update", Value: "true", Default: "false", Set: true},
		{Key: "auto_update_level", Value: "minor", Default: "major", Set: true},
		{Key: "history_days", Value: "30", Default: "365", Set: true},
		{Key: "history_chunk_days", Value: "10", Default: "100", Set: true},
		{Key: "working_hours", Value: "6", Default: "8", Set: true},
		{Key: "dora_days", Value: "30", Default: "30", Set: true},
		{Key: "issues_page", Value: "false", Default: "true", Set: true},
		{Key: "days_page", Value: "true", Default: "false", Set: true},
		{Key: "numbers_scoring_page", Value: "true", Default: "unlisted", Set: true},
		{Key: "history_page", Value: "false", Default: "unlisted", Set: true},
		{Key: "tbd_page", Value: "true", Default: "true", Set: true},
		{Key: "week_page", Value: "false", Default: "true", Set: true},
		{Key: "tbd_figures", Value: "all", Default: "median", Set: true},
		{Key: "tbd_time_to_main", Value: "false", Default: "true", Set: true},
		{Key: "tbd_pr_lead_time", Value: "false", Default: "true", Set: true},
		{Key: "tbd_bot_pr_lead_time", Value: "false", Default: "true", Set: true},
		{Key: "same_developer", Value: "[[maintainer, assistant-account]]", Default: "[]", Set: true},
		{Key: "thousands_separator", Value: "comma", Default: "narrow_space", Set: true},
	})
}

// TestEveryRejectedSettingIsListedInOrder (forsgren#183): a file with several
// settings that are not accepted loads, every default is in force and each
// rejection is listed, in the order of the settings.
func TestEveryRejectedSettingIsListedInOrder(t *testing.T) {
	bad := "days_page: yes\ndora_days: 60\nhistory_days: 0\nauto_update: maybe\nview: weekly\nworking_hours: 6\n"
	got, err := parse([]byte(bad + valid))
	if err != nil {
		t.Fatal(err)
	}
	var keys []string
	for _, r := range got.Rejected {
		keys = append(keys, r.Key)
	}
	want := []string{"view", "auto_update", "history_days", "dora_days", "days_page"}
	if !slices.Equal(keys, want) {
		t.Errorf("want rejections %v, got %v", want, keys)
	}
	if got.WorkingHours != 6 {
		t.Errorf("want the accepted working_hours 6 read, got %d", got.WorkingHours)
	}
}

// TestAListOrMappingForASettingIsRejectedNotSyntax (forsgren#183): a list or a
// mapping where a setting wants a plain value is not accepted like any other
// value: the default is in force and the rejection shows the value in YAML's
// flow form, with the key's own reason; it is no ErrSyntax.
func TestAListOrMappingForASettingIsRejectedNotSyntax(t *testing.T) {
	keys := []struct {
		key, reason, def string
		sentinel         error
	}{
		{"view", "use standard, numbers or scoring", "standard", ErrView},
		{"auto_update", "use true or false", "false", ErrAutoUpdate},
		{"auto_update_level", "use patch, minor or major", "major", ErrAutoUpdateLevel},
		{"history_days", "use a whole number of days from 30 to 1825", "365", ErrHistoryDays},
		{"history_chunk_days", "use a whole number of days from 1 to 365", "100", ErrHistoryChunkDays},
		{"working_hours", "use a whole number of hours from 1 to 24", "8", ErrWorkingHours},
		{"dora_days", "use 30, 90 or 180", "30", ErrDoraDays},
		{"issues_page", "use true, unlisted or false", "true", ErrIssuesPage},
		{"days_page", "use true, unlisted or false", "false", ErrDaysPage},
		{"numbers_scoring_page", "use true, unlisted or false", "unlisted", ErrNumbersScoringPage},
		{"history_page", "use true, unlisted or false", "unlisted", ErrHistoryPage},
		{"tbd_page", "use true, unlisted or false", "true", ErrTbdPage},
		{"week_page", "use true or false", "true", ErrWeekPage},
		{"tbd_figures", "use median or all", "median", ErrTbdFigures},
		{"tbd_time_to_main", "use true or false", "true", ErrTbdTimeToMain},
		{"tbd_pr_lead_time", "use true or false", "true", ErrTbdPRLeadTime},
		{"tbd_bot_pr_lead_time", "use true or false", "true", ErrTbdBotPRLeadTime},
		{"sub_rows", "use true or false", "true", ErrSubRows},
		{"same_developer", sameDeveloperShape, "[]", ErrSameDeveloper},
		{"thousands_separator", "use narrow_space, comma or none", "narrow_space", ErrThousandsSeparator},
	}
	for _, k := range keys {
		for written, yaml := range map[string]string{"[a, b]": "\n  - a\n  - b", "{a: b}": "\n  a: b"} {
			t.Run(k.key+" "+written, func(t *testing.T) {
				got, err := parse([]byte(k.key + ":" + yaml + "\n" + valid))
				if err != nil || got.written[k.key] {
					t.Fatalf("want no error and %s not written, got %v, %v", k.key, got.written, err)
				}
				wantRejection(t, got.Rejected, k.sentinel, [4]string{k.key, written, k.reason, k.def})
			})
		}
	}
}

// TestALongListIsCutWhereTheRejectionShowsIt (forsgren#183): the value of a
// list as written is cut to 40 characters and three dots, on one line.
func TestALongListIsCutWhereTheRejectionShowsIt(t *testing.T) {
	list := "view: [" + strings.Repeat("aaaa, ", 20) + "z]\n"
	got, err := parse([]byte(list + valid))
	if err != nil || len(got.Rejected) != 1 {
		t.Fatalf("want one rejection and no error, got %v, %v", got.Rejected, err)
	}
	written := got.Rejected[0].Written
	if want := "[aaaa, aaaa, aaaa, aaaa, aaaa, aaaa, aaa..."; written != want {
		t.Errorf("want %q, got %q", want, written)
	}
}

// TestAnAliasInsideAValueShowsItsName (forsgren#183): an alias in a list is
// shown as *name, a nested list or mapping in flow form.
func TestAnAliasInsideAValueShowsItsName(t *testing.T) {
	got, err := parse([]byte("view: [&x one, *x, {k: [v]}]\n" + valid))
	if err != nil || len(got.Rejected) != 1 {
		t.Fatalf("want one rejection and no error, got %v, %v", got.Rejected, err)
	}
	if want := "[one, *x, {k: [v]}]"; got.Rejected[0].Written != want {
		t.Errorf("want %q, got %q", want, got.Rejected[0].Written)
	}
}

// TestSettingsCarriesEachRejection (forsgren#183): a setting that is not
// accepted lists the default in force, as not written, with the value as
// written and the reason; the other settings carry neither.
func TestSettingsCarriesEachRejection(t *testing.T) {
	wantSettings(t, "view: weekly\nhistory_days: 0\nworking_hours: 6\n", []Setting{
		{Key: "view", Value: "standard", Default: "standard", Written: "weekly", Reason: "use standard, numbers or scoring"},
		{Key: "sub_rows", Value: "true", Default: "true"},
		{Key: "auto_update", Value: "false", Default: "false"},
		{Key: "auto_update_level", Value: "major", Default: "major"},
		{Key: "history_days", Value: "365", Default: "365", Written: "0",
			Reason: "use a whole number of days from 30 to 1825"},
		{Key: "history_chunk_days", Value: "100", Default: "100"},
		{Key: "working_hours", Value: "6", Default: "8", Set: true},
		{Key: "dora_days", Value: "30", Default: "30"},
		{Key: "issues_page", Value: "true", Default: "true"},
		{Key: "days_page", Value: "false", Default: "false"},
		{Key: "numbers_scoring_page", Value: "unlisted", Default: "unlisted"},
		{Key: "history_page", Value: "unlisted", Default: "unlisted"},
		{Key: "tbd_page", Value: "true", Default: "true"},
		{Key: "week_page", Value: "true", Default: "true"},
		{Key: "tbd_figures", Value: "median", Default: "median"},
		{Key: "tbd_time_to_main", Value: "true", Default: "true"},
		{Key: "tbd_pr_lead_time", Value: "true", Default: "true"},
		{Key: "tbd_bot_pr_lead_time", Value: "true", Default: "true"},
		{Key: "same_developer", Value: "[]", Default: "[]"},
		{Key: "thousands_separator", Value: "narrow_space", Default: "narrow_space"},
	})
}

// wantSettings wants the settings of the config the keys, then a valid
// projects list, make to be exactly want.
func wantSettings(t *testing.T, keys string, want []Setting) {
	t.Helper()
	got, err := parse([]byte(keys + valid))
	if err != nil {
		t.Fatal(err)
	}
	if s := got.Settings(); !slices.Equal(s, want) {
		t.Errorf("want settings %v, got %v", want, s)
	}
}

// TestSettingsShowsARejectedDoraDaysLikeTheOtherKeys (forsgren#178, #183): a
// dora_days that is not accepted lists 30 as not written, with the value as
// written and the reason.
func TestSettingsShowsARejectedDoraDaysLikeTheOtherKeys(t *testing.T) {
	got, err := parse([]byte("dora_days: 60\n" + valid))
	if err != nil {
		t.Fatal(err)
	}
	want := Setting{Key: "dora_days", Value: "30", Default: "30", Written: "60", Reason: "use 30, 90 or 180"}
	if !slices.Contains(got.Settings(), want) {
		t.Errorf("want the settings to hold %+v, got %+v", want, got.Settings())
	}
}

// TestSettingsExposeTheDefaultOfEveryKey (forsgren#169): every key lists its
// default, the same whether the file leaves the key out or writes another
// value, so the settings page can show it beside the current value.
func TestSettingsExposeTheDefaultOfEveryKey(t *testing.T) {
	want := []string{
		"standard", "true", "false", "major", "365", "100", "8", "30",
		"true", "false", "unlisted", "unlisted", "true", "true", "median", "true", "true", "true", "[]", "narrow_space",
	}
	for _, file := range []string{"", "history_days: 90\nview: numbers\n"} {
		got, err := parse([]byte(file + valid))
		if err != nil {
			t.Fatal(err)
		}
		var defaults []string
		for _, s := range got.Settings() {
			defaults = append(defaults, s.Default)
		}
		if !slices.Equal(defaults, want) {
			t.Errorf("file %q: want defaults %v, got %v", file, want, defaults)
		}
	}
}
