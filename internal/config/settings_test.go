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
	got, err := parse([]byte("history_days: 30\n" + valid))
	if err != nil {
		t.Fatal(err)
	}
	want := []Setting{
		{"view", "standard", false},
		{"auto_update", "false", false},
		{"auto_update_level", "major", false},
		{"history_days", "30", true},
		{"history_chunk_days", "100", false},
		{"working_hours", "8", false},
		{"issues_page", "true", false},
		{"days_page", "false", false},
	}
	if s := got.Settings(); !slices.Equal(s, want) {
		t.Errorf("want settings %v, got %v", want, s)
	}
}

// TestSettingsMarksEveryWrittenKeySet (forsgren#74): a file that writes all
// eight keys has all of them Set, with the written values.
func TestSettingsMarksEveryWrittenKeySet(t *testing.T) {
	all := "view: numbers\nauto_update: true\nauto_update_level: minor\n" +
		"history_days: 30\nhistory_chunk_days: 10\nworking_hours: 6\nissues_page: false\ndays_page: true\n"
	got, err := parse([]byte(all + valid))
	if err != nil {
		t.Fatal(err)
	}
	want := []Setting{
		{"view", "numbers", true},
		{"auto_update", "true", true},
		{"auto_update_level", "minor", true},
		{"history_days", "30", true},
		{"history_chunk_days", "10", true},
		{"working_hours", "6", true},
		{"issues_page", "false", true},
		{"days_page", "true", true},
	}
	if s := got.Settings(); !slices.Equal(s, want) {
		t.Errorf("want settings %v, got %v", want, s)
	}
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
		{"history_days", "use a whole number of days from 1 to 1825", "365", ErrHistoryDays},
		{"history_chunk_days", "use a whole number of days from 1 to 365", "100", ErrHistoryChunkDays},
		{"working_hours", "use a whole number of hours from 1 to 24", "8", ErrWorkingHours},
		{"dora_days", "use 30, 90 or 180", "30", ErrDoraDays},
		{"issues_page", "use true or false", "true", ErrIssuesPage},
		{"days_page", "use true or false", "false", ErrDaysPage},
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
