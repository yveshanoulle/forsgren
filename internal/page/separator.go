package page

import (
	"strings"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// withSeparators is the page with the narrow no-break space metrics.GroupDigits
// writes in every count of 1000 or more replaced by what the config's
// thousands_separator says (the comma, the period, nothing, or, for
// narrow_space or empty for a Data not made from a config, the space as it
// is), and the decimal mark metrics.DecimalMark stands for in every decimal
// replaced by what decimal_separator says (the comma, or the point, also for
// empty). The two placeholders differ, so no mark is swapped twice
// (forsgren#528, #536).
func withSeparators(page string, data Data) string {
	return strings.NewReplacer(metrics.ThousandsSpace, thousandsMark(data.ThousandsSeparator),
		metrics.DecimalMark, decimalMark(data.DecimalSeparator)).Replace(page)
}

// thousandsMark is what the thousands_separator setting writes between the
// groups of digits.
func thousandsMark(setting string) string {
	switch setting {
	case config.ThousandsComma:
		return ","
	case config.ThousandsPeriod:
		return "."
	case config.ThousandsNone:
		return ""
	}
	return metrics.ThousandsSpace
}

// decimalMark is what the decimal_separator setting writes between the whole
// part and the fraction.
func decimalMark(setting string) string {
	if setting == config.DecimalComma {
		return ","
	}
	return "."
}

// decimalText is text with every point of a decimal in it, "1.0 or 2.5", as
// the DecimalMark, for the legend's examples (forsgren#536).
func decimalText(text string) string { return strings.ReplaceAll(text, ".", metrics.DecimalMark) }
