package metrics

import "time"

// last30Days is the length of the 30-day window in days.
const last30Days = int(last30)

// bandOfAgeOver is the band of a row whose first successful deployment was
// created at first (forsgren#69), over a window of days (30, 90 or 180,
// forsgren#178). A row younger than the window at now has not had a whole
// window to deploy in, so its band uses its window count scaled to the
// window: the count times the days over its age in whole days, at least 1. An
// older row's band is BandOverDays'. Last30 itself stays the unscaled count.
func bandOfAgeOver(count, count180, workingHours, days int, first, now time.Time) Band {
	age := now.Sub(first)
	if age >= time.Duration(days)*day {
		return BandOverDays(count, count180, workingHours, days)
	}
	ageDays := max(1, int(age/day))
	return BandOverDays(count*days/ageDays, count180, workingHours, days)
}

// earlier is the earlier of the two times, the zero time counting as none.
func earlier(a, b time.Time) time.Time {
	if a.IsZero() || b.Before(a) {
		return b
	}
	return a
}
