package metrics

// The Failed and Fail rate cells of the Week table (forsgren#545, decision
// #546, forsgren#547). A failed deployment is one of state failure. Failed is
// a count in Total and, per weekday, the share of the row's failures on it;
// Fail rate is the failures over the successful plus the failed deployments,
// of the weekday or of the window in Total; deployments of state other are
// left out of both, as in the change failure rate. The highest weekday of
// each is marked, every tied day, none for a row without failures.

// FailedTotalCell is the row's failed deployments of the window as a count.
func (r WeekRow) FailedTotalCell() string { return GroupDigits(sum(r.Failed)) }

// FailRateTotalCell is the failed deployments of the window over its
// successful plus failed ones, written as the shares are; a dash for a row
// with neither.
func (r WeekRow) FailRateTotalCell() string {
	return shareOf(sum(r.Failed), sum(r.Deployments)+sum(r.Failed))
}

// FailedShareCell is the share of the row's failed deployments on weekday day
// (0 Monday to 6 Sunday); a dash for a row with none.
func (r WeekRow) FailedShareCell(day int) string { return shareOf(r.Failed[day], sum(r.Failed)) }

// FailRateCell is the failed deployments of weekday day over its successful
// plus failed ones; a dash for a weekday with neither.
func (r WeekRow) FailRateCell(day int) string { return shareOf(r.Failed[day], r.rated(day)) }

// rated are the deployments of weekday day that count in the fail rate: the
// successful and the failed ones, not the other states.
func (r WeekRow) rated(day int) int { return r.Deployments[day] + r.Failed[day] }

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
		// failed[other]/rated(other) > failed[day]/rated(day), cross-multiplied.
		if r.rated(other) > 0 && r.Failed[other]*r.rated(day) > r.Failed[day]*r.rated(other) {
			return false
		}
	}
	return true
}

// DeploymentsHighest says whether weekday day has the most successful
// deployments of the row, so the highest Deploys share, a tie marking every
// tied day; false for a row without deployments (forsgren#597).
func (r WeekRow) DeploymentsHighest(day int) bool {
	return r.Deployments[day] > 0 && r.Deployments[day] == maxOf(r.Deployments)
}

// maxOf is the largest of the per-weekday counts.
func maxOf(days [weekdays]int) int {
	most := 0
	for _, n := range days {
		most = max(most, n)
	}
	return most
}
