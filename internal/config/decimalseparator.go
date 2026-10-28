package config

// The decimal_separator key (forsgren#536): how the pages write the decimal
// mark of a figure with a decimal, and its pairing with thousands_separator.

import (
	"errors"
	"slices"

	"go.yaml.in/yaml/v3"
)

// The decimal marks: a point (the default) or a comma.
const (
	DecimalPoint = "point"
	DecimalComma = "comma"

	// DefaultDecimalSeparator is the mark used when the file writes none.
	DefaultDecimalSeparator = DecimalPoint
)

// ErrDecimalSeparator wraps the Rejection of a decimal_separator that is not
// accepted, or that is the same mark as thousands_separator.
var ErrDecimalSeparator = errors.New("invalid decimal_separator")

// decimalSeparatorValues are the values decimal_separator accepts, in the
// order the settings page lists them.
var decimalSeparatorValues = []string{DecimalPoint, DecimalComma}

// decimalSeparatorKey is decimal_separator as a Rejection names it.
var decimalSeparatorKey = refusable{ErrDecimalSeparator, "decimal_separator", DefaultDecimalSeparator}

// checkDecimalSeparator is decimal_separator as written, DefaultDecimalSeparator
// when the file has none, or the default and the Rejection naming the valid
// values.
func checkDecimalSeparator(n yaml.Node) (string, *Rejection) {
	if !hasValue(n) {
		return DefaultDecimalSeparator, nil
	}
	if n.Kind == yaml.ScalarNode && slices.Contains(decimalSeparatorValues, n.Value) {
		return n.Value, nil
	}
	return DefaultDecimalSeparator, decimalSeparatorKey.reject(n, "use "+DecimalPoint+" or "+DecimalComma)
}

// separators is thousands_separator and decimal_separator as they stand in
// force and the Rejections of the two: each checked alone, then both reverted
// to their defaults when they resolve to the same mark (forsgren#536).
func (f fileConfig) separators() (thousands, decimal string, rejected []*Rejection) {
	thousands, thousandsRejection := checkThousandsSeparator(f.ThousandsSeparator)
	decimal, decimalRejection := checkDecimalSeparator(f.DecimalSeparator)
	if conflict := separatorConflict(thousands, decimal, f); conflict != nil {
		return DefaultThousandsSeparator, DefaultDecimalSeparator, []*Rejection{conflict["thousands_separator"],
			conflict["decimal_separator"]}
	}
	return thousands, decimal, []*Rejection{thousandsRejection, decimalRejection}
}

// markOf is the character a thousands_separator or decimal_separator value
// writes between digits: "," for comma, "." for period and point, "" for the
// values that write none or a space.
func markOf(value string) string {
	switch value {
	case ThousandsComma:
		return ","
	case ThousandsPeriod, DecimalPoint:
		return "."
	}
	return ""
}

// separatorConflict is the Rejections of a thousands_separator and a
// decimal_separator, both accepted on their own, that resolve to the same
// mark (forsgren#536, decision #537 A): one for each key the file writes, by
// key, with both defaults in force; nil when the marks differ. The reason names both
// values, the default one as such, and the mark.
func separatorConflict(thousands, decimal string, f fileConfig) map[string]*Rejection {
	mark := markOf(thousands)
	if mark == "" || mark != markOf(decimal) {
		return nil
	}
	reason := "thousands_separator " + thousands + writtenNote(f.ThousandsSeparator) +
		" and decimal_separator " + decimal + writtenNote(f.DecimalSeparator) + " are both the mark \"" + mark +
		"\"; use different marks; both separators revert to their defaults, " + DefaultThousandsSeparator + " and " +
		DefaultDecimalSeparator
	rejected := map[string]*Rejection{}
	if hasValue(f.ThousandsSeparator) {
		rejected["thousands_separator"] = thousandsSeparatorKey.reject(f.ThousandsSeparator, reason)
	}
	if hasValue(f.DecimalSeparator) {
		rejected["decimal_separator"] = decimalSeparatorKey.reject(f.DecimalSeparator, reason)
	}
	return rejected
}

// writtenNote is " (the default)" for a key the file does not write.
func writtenNote(n yaml.Node) string {
	if hasValue(n) {
		return ""
	}
	return " (the default)"
}
