package metrics

import (
	"fmt"
	"time"
)

// tbdDuration writes d for a cell of the TBD page (forsgren#403): the
// shortDuration of the other pages stays as it is. Hours and minutes are
// "3 h 22", whole hours "2 h", minutes alone "7 m", under a minute "< 1 m",
// a day or more as shortDuration writes it, "1 d 6 h". Each part is cut down,
// never rounded up, as shortDuration cuts it.
func tbdDuration(d time.Duration) string {
	switch {
	case d < time.Minute:
		return "< 1 m"
	case d < time.Hour:
		return fmt.Sprintf("%d m", d/time.Minute)
	case d < day:
		return hoursAndMinutes(int(d/time.Hour), int(d%time.Hour/time.Minute))
	default:
		return twoParts(int(d/day), "d", int(d%day/time.Hour), "h")
	}
}

// hoursAndMinutes is "3 h 22", the minutes left out at 0: "2 h".
func hoursAndMinutes(h, m int) string {
	if m == 0 {
		return fmt.Sprintf("%d h", h)
	}
	return fmt.Sprintf("%d h %d", h, m)
}
