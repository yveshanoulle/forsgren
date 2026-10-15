package page

// The History page's notice (forsgren#198): while only the last 6 months have
// data, the page says since when, and when the first half-year gets a column.

import (
	"fmt"
	"time"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// HistoryNotice is the line under the history page's how-to-read line while
// the last 6 months are its only column (forsgren#198). It is empty otherwise:
// with no column or several the page needs none, and a single half-year
// column, or no known first deployment, leaves nothing to say.
func (d Data) HistoryNotice() string {
	if !d.onlyTheRollingColumn() || d.FirstDeployment.IsZero() {
		return ""
	}
	return historyNotice(d.FirstDeployment, d.History[0].Period.End, d.HistoryDays)
}

// onlyTheRollingColumn says whether the last 6 months are the history page's
// one column.
func (d Data) onlyTheRollingColumn() bool { return len(d.History) == 1 && d.History[0].Period.Rolling }

// historyNotice is the notice for a first deployment at first, rendered at
// now: the day of that deployment, then when the half-year it falls in gets a
// column. While that half-year is still running, it appears the day after it
// ends, and history_days must reach back over all of it plus the render day;
// once it is over, history_days must reach back from now to its start.
// historyDays is 0 when it is unknown, which counts as enough.
func historyNotice(first, now time.Time, historyDays int) string {
	label, start, next := metrics.HalfYearOf(first)
	head := fmt.Sprintf("Only the last 6 months have data so far: the first deployment is %s.",
		first.UTC().Format(dateLayout))
	if next.After(now) {
		return head + comingHalfYear(label, next, wholeDays(next.Sub(start))+1, historyDays)
	}
	return head + shownHalfYear(label, wholeDays(now.Sub(start)), historyDays)
}

// wholeDays is d in days, rounded up.
func wholeDays(d time.Duration) int { return int((d + dayLength - 1) / dayLength) }

// dayLength is a day, in the UTC days the periods count.
const dayLength = 24 * time.Hour

// comingHalfYear is the notice's sentence on a half-year that is not complete
// yet: it appears on next, if historyDays reaches back the need days.
func comingHalfYear(label string, next time.Time, need, historyDays int) string {
	appears := fmt.Sprintf(" The first half-year, %s, appears on %s", label, next.Format(dateLayout))
	if historyDays == 0 || historyDays >= need {
		return appears + "."
	}
	return fmt.Sprintf("%s if history_days is at least %d; it is %d, so raise it in forsgren.config.yml.",
		appears, need, historyDays)
}

// shownHalfYear is the notice's sentence on a complete half-year that has no
// column: history_days is too short for the need days, or the collection has
// not read back to its start yet.
func shownHalfYear(label string, need, historyDays int) string {
	if historyDays == 0 || historyDays >= need {
		return fmt.Sprintf(" The first half-year, %s, is not shown yet: "+
			"the history is still being read back to its start.", label)
	}
	return fmt.Sprintf(" The first half-year, %s, is not shown because history_days is %d: "+
		"raise it to at least %d in forsgren.config.yml.", label, historyDays, need)
}
