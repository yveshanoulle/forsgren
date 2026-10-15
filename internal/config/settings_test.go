package config

import (
	"slices"
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
