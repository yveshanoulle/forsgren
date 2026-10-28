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

// acceptedSets are the fixed sets of the keys that are not page keys, by key.
var acceptedSets = map[string][]string{
	"view":                 viewValues,
	"auto_update":          slices.Sorted(maps.Keys(booleans)),
	"sub_rows":             slices.Sorted(maps.Keys(booleans)),
	"week_page":            slices.Sorted(maps.Keys(booleans)),
	"tbd_time_to_main":     slices.Sorted(maps.Keys(booleans)),
	"tbd_pr_lead_time":     slices.Sorted(maps.Keys(booleans)),
	"tbd_bot_pr_lead_time": slices.Sorted(maps.Keys(booleans)),
	"auto_update_level":    levelValues,
	"dora_days":            numbersOf(doraWindows),
	"tbd_figures":          tbdFiguresValues,
	"thousands_separator":  thousandsSeparatorValues,
	"decimal_separator":    decimalSeparatorValues,
}

// Accepted is the values the key accepts when they are a fixed set, sorted
// as written in the settings page's list, nil for a key that takes a number
// of days or hours. The loader checks against the same sets, so the settings
// page can be held to list every one (forsgren#79, #200, #423).
func Accepted(key string) []string {
	if set, ok := acceptedSets[key]; ok {
		return slices.Clone(set)
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
