package metrics

import "time"

// last30Days is the length of the 30-day window in days.
const last30Days = int(last30)

// bandOfAge is the band of a row whose first successful deployment was
// created at first (forsgren#69). A row younger than 30 days at now has not
// had a whole window to deploy in, so its band uses its 30-day count scaled
// to 30 days: count30 times 30 over its age in whole days, at least 1. An
// older row's band is BandOf's. Last30 itself stays the unscaled count. Over
// a window of days the same holds with that window in place of the 30
// (bandOfAgeOver, forsgren#178).
func bandOfAge(count30, count180, workingHours int, first, now time.Time) Band {
	return bandOfAgeOver(count30, count180, workingHours, last30Days, first, now)
}

// bandOfAgeOver is bandOfAge over a window of days (30, 90 or 180): a row
// younger than the window is scaled to it, count × days over its age in whole
// days, at least 1 (forsgren#178).
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
