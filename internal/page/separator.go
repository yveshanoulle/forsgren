package page

import (
	"strings"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// withSeparator is the page with the narrow no-break space metrics.GroupDigits
// writes in every count of 1000 or more replaced by what the config's
// thousands_separator says: the comma, nothing, or (narrow_space, or empty
// for a Data not made from a config) the space as it is (forsgren#528).
func withSeparator(page, setting string) string {
	switch setting {
	case config.ThousandsComma:
		return strings.ReplaceAll(page, metrics.ThousandsSpace, ",")
	case config.ThousandsNone:
		return strings.ReplaceAll(page, metrics.ThousandsSpace, "")
	}
	return page
}
