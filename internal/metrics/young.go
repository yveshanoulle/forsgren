package metrics

import "time"

// scaledToAge is the count over a window of days (30, 90 or 180,
// forsgren#178) that a row's band uses, its first successful deployment
// created at first (forsgren#69). A row younger than the window at now has not
// had a whole window to deploy in, so its count is scaled to the window: the
// count times the days over its age in whole days, at least 1. An older row's
// count is its own. InWindow itself stays the unscaled count.
func scaledToAge(count, days int, first, now time.Time) int {
	age := now.Sub(first)
	if age >= time.Duration(days)*day {
		return count
	}
	return count * days / max(1, int(age/day))
}

// earlier is the earlier of the two times, the zero time counting as none.
func earlier(a, b time.Time) time.Time {
	if a.IsZero() || b.Before(a) {
		return b
	}
	return a
}
