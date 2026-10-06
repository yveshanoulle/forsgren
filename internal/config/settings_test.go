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
		{"auto_update_level", "none", false},
		{"history_days", "30", true},
		{"history_chunk_days", "100", false},
		{"working_hours", "8", false},
	}
	if s := got.Settings(); !slices.Equal(s, want) {
		t.Errorf("want settings %v, got %v", want, s)
	}
}

// TestSettingsMarksEveryWrittenKeySet (forsgren#74): a file that writes all
// six keys has all of them Set, with the written values.
func TestSettingsMarksEveryWrittenKeySet(t *testing.T) {
	all := "view: numbers\nauto_update: true\nauto_update_level: minor\n" +
		"history_days: 30\nhistory_chunk_days: 10\nworking_hours: 6\n"
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
	}
	if s := got.Settings(); !slices.Equal(s, want) {
		t.Errorf("want settings %v, got %v", want, s)
	}
}
