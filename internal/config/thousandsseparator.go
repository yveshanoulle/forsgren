package config

// The thousands_separator key (forsgren#528, decisions #529 B and its
// parameter): how the pages write a count of 1000 or more.

import (
	"errors"
	"slices"

	"go.yaml.in/yaml/v3"
)

// The separators: a narrow no-break space (the default), a comma, or none.
// There is no period: the pages keep the decimal point, so a period would
// clash with it.
const (
	ThousandsNarrowSpace = "narrow_space"
	ThousandsComma       = "comma"
	ThousandsNone        = "none"

	// DefaultThousandsSeparator is the separator used when the file writes none.
	DefaultThousandsSeparator = ThousandsNarrowSpace
)

// ErrThousandsSeparator wraps the Rejection of a thousands_separator that is
// not accepted.
var ErrThousandsSeparator = errors.New("invalid thousands_separator")

// thousandsSeparatorValues are the values thousands_separator accepts, in the
// order the settings page lists them.
var thousandsSeparatorValues = []string{ThousandsNarrowSpace, ThousandsComma, ThousandsNone}

// thousandsSeparatorKey is thousands_separator as a Rejection names it.
var thousandsSeparatorKey = refusable{ErrThousandsSeparator, "thousands_separator", DefaultThousandsSeparator}

// checkThousandsSeparator is thousands_separator as written,
// DefaultThousandsSeparator when the file has none, or the default and the
// Rejection naming the valid values.
func checkThousandsSeparator(n yaml.Node) (string, *Rejection) {
	if !hasValue(n) {
		return DefaultThousandsSeparator, nil
	}
	if n.Kind == yaml.ScalarNode && slices.Contains(thousandsSeparatorValues, n.Value) {
		return n.Value, nil
	}
	return DefaultThousandsSeparator, thousandsSeparatorKey.reject(n,
		"use "+ThousandsNarrowSpace+", "+ThousandsComma+" or "+ThousandsNone)
}
