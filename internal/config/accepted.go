package config

import (
	"maps"
	"slices"
	"strconv"
)

// The sets of values of the keys that take a fixed one: the loader checks a
// value against them, and Accepted hands them out (forsgren#200). The page
// keys' set, pageModeValues, is in pagemode.go.
var (
	viewValues  = []string{ViewStandard, ViewNumbers, ViewScoring}
	levelValues = []string{LevelPatch, LevelMinor, LevelMajor}
	doraWindows = []int{DefaultDoraDays, DoraDays90, DoraDays180}
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
	if isPageKey(key) {
		return pageModeNames()
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
