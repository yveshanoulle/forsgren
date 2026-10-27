package metrics

import (
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
)

// ReportBounds are the first and the last instant of the DORA window of
// dora_days (0 is the default 30 days) at the render time now, in UTC: the
// rolling window the metrics count over (window.holds), so the footer's
// Report Start and Report End and the Week page's sentence are the very
// bounds the figures use (forsgren#542, decision #543 A).
func ReportBounds(days int, now time.Time) (start, end time.Time) {
	w := window(config.DoraWindow(days))
	return now.Add(-time.Duration(w) * day).UTC(), now.UTC()
}
