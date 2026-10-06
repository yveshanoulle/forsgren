package metrics

import "time"

// bandOfAge is the band of a row whose first successful deployment was
// created at first (forsgren#69). A row younger than 30 days at now has not
// had a whole window to deploy in, so its band uses its 30-day count scaled
// to 30 days: last30 times 30 over its age in whole days, at least 1. An
// older row's band is BandOf's. Last30 itself stays the unscaled count.
func bandOfAge(last30, last180 int, first, now time.Time) Band {
	age := now.Sub(first)
	if age >= time.Duration(last30Days)*day {
		return BandOf(last30, last180)
	}
	days := max(1, int(age/day))
	return BandOf(last30*last30Days/days, last180)
}

// last30Days is the length of the 30-day window in days.
const last30Days = int(last30)

// earlier is the earlier of the two times, the zero time counting as none.
func earlier(a, b time.Time) time.Time {
	if a.IsZero() || b.Before(a) {
		return b
	}
	return a
}
