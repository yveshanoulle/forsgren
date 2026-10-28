package metrics

// The Failed and Fail rate cells of the Week table (forsgren#545, decision
// #546). A failed deployment is one of state failure; a finished one is a
// success, a failure or an other. Failed is a count in Total and, per
// weekday, the share of the row's failures on it; Fail rate is the failures
// over the finished deployments, of the weekday or of the window in Total.
// The highest weekday of each is marked, every tied day, none for a row
// without failures.

// FailedTotalCell is the row's failed deployments of the window as a count.
func (r WeekRow) FailedTotalCell() string { return GroupDigits(sum(r.Failed)) }

// FailRateTotalCell is the failed deployments of the window over its finished
// ones, written as the shares are; a dash for a row with none finished.
func (r WeekRow) FailRateTotalCell() string { return shareOf(sum(r.Failed), sum(r.Finished)) }

// FailedShareCell is the share of the row's failed deployments on weekday day
// (0 Monday to 6 Sunday); a dash for a row with none.
func (r WeekRow) FailedShareCell(day int) string { return shareOf(r.Failed[day], sum(r.Failed)) }

// FailRateCell is the failed deployments of weekday day over its finished
// ones; a dash for a weekday without any.
func (r WeekRow) FailRateCell(day int) string { return shareOf(r.Failed[day], r.Finished[day]) }

// FailedHighest says whether weekday day has the most failed deployments of
// the row, a tie marking every tied day; false for a row without failures.
func (r WeekRow) FailedHighest(day int) bool {
	return r.Failed[day] > 0 && r.Failed[day] == maxOf(r.Failed)
}

// FailRateHighest says whether weekday day has the highest fail rate of the
// row, a tie marking every tied day; false for a row without failures.
func (r WeekRow) FailRateHighest(day int) bool {
	if r.Failed[day] == 0 {
		return false
	}
	for other := range weekdays {
		// failed[other]/finished[other] > failed[day]/finished[day], cross-multiplied.
		if r.Finished[other] > 0 && r.Failed[other]*r.Finished[day] > r.Failed[day]*r.Finished[other] {
			return false
		}
	}
	return true
}

// maxOf is the largest of the per-weekday counts.
func maxOf(days [weekdays]int) int {
	most := 0
	for _, n := range days {
		most = max(most, n)
	}
	return most
}
