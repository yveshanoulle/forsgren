package metrics

import (
	"testing"
	"time"
)

// TestTbdDurationWritesEveryBand (forsgren#403): hours with minutes "3 h 22",
// whole hours "2 h" (never "2 h 0"), minutes alone "7 m", under a minute
// "< 1 m", days as shortDuration writes them; every part cut down.
func TestTbdDurationWritesEveryBand(t *testing.T) {
	const s = time.Second
	cases := map[string]struct {
		d    time.Duration
		want string
	}{
		"zero":             {0, "< 1 m"},
		"59 seconds":       {59 * s, "< 1 m"},
		"60 seconds":       {60 * s, "1 m"},
		"119 seconds":      {119 * s, "1 m"},
		"7 minutes":        {7 * time.Minute, "7 m"},
		"59 min 59 s":      {59*time.Minute + 59*s, "59 m"},
		"1 h":              {time.Hour, "1 h"},
		"1 h 59 s":         {time.Hour + 59*s, "1 h"},
		"1 h 1 min":        {time.Hour + time.Minute, "1 h 1"},
		"2 h":              {2 * time.Hour, "2 h"},
		"3 h 22 min":       {3*time.Hour + 22*time.Minute, "3 h 22"},
		"3 h 22 min 59 s":  {3*time.Hour + 22*time.Minute + 59*s, "3 h 22"},
		"23 h 59 min":      {23*time.Hour + 59*time.Minute, "23 h 59"},
		"23 h 59 min 59 s": {23*time.Hour + 59*time.Minute + 59*s, "23 h 59"},
		"1 d":              {day, "1 d"},
		"1 d 59 min":       {day + 59*time.Minute, "1 d"},
		"1 d 6 h":          {day + 6*time.Hour, "1 d 6 h"},
		"1 d 23 h 59 min":  {day + 23*time.Hour + 59*time.Minute, "1 d 23 h"},
		"12 d 3 h":         {12*day + 3*time.Hour, "12 d 3 h"},
	}
	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			if got := tbdDuration(c.d); got != c.want {
				t.Errorf("tbdDuration(%v): want %q, got %q", c.d, c.want, got)
			}
		})
	}
}
