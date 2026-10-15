package config

import (
	"maps"
	"slices"
	"strconv"
)

// The sets of values of the keys that take a fixed one: the loader checks a
// value against them, and Accepted hands them out (forsgren#200).
var (
	viewValues     = []string{ViewStandard, ViewNumbers, ViewScoring}
	levelValues    = []string{LevelPatch, LevelMinor, LevelMajor}
	pageModeValues = []PageMode{PageOn, PageUnlisted, PageOff}
	doraWindows    = []int{DefaultDoraDays, DoraDays90, DoraDays180}
)

// Accepted is the values the key accepts when they are a fixed set, sorted
// as written in the settings page's list, nil for a key that takes a number
// of days or hours. The loader checks against the same sets, so the settings
// page can be held to list every one (forsgren#79, #200).
func Accepted(key string) []string {
	switch key {
	case "view":
		return slices.Clone(viewValues)
	case "auto_update":
		return slices.Sorted(maps.Keys(booleans))
	case "auto_update_level":
		return slices.Clone(levelValues)
	case "dora_days":
		return numbersOf(doraWindows)
	}
	if page, ok := pageKeys[key]; ok {
		return page
	}
	return nil
}

// numbersOf is the numbers as written in the file.
func numbersOf(numbers []int) []string {
	out := make([]string, len(numbers))
	for i, n := range numbers {
		out[i] = strconv.Itoa(n)
	}
	return out
}

// pageKeys are the page keys, each with the values a page key accepts.
var pageKeys = map[string][]string{"issues_page": pageModeNames(), "days_page": pageModeNames(),
	"numbers_scoring_page": pageModeNames(), "history_page": pageModeNames()}

// pageModeNames are the PageModes as written in the file.
func pageModeNames() []string {
	out := make([]string, len(pageModeValues))
	for i, m := range pageModeValues {
		out[i] = string(m)
	}
	return out
}
