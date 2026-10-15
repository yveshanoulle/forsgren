package config

import (
	"strconv"
	"testing"
)

// TestWorkingHoursIsRead (forsgren#71): the optional top-level working_hours
// key, a whole number from 1 to 24; 8 when the key is left out.
func TestWorkingHoursIsRead(t *testing.T) {
	cases := []struct {
		name string
		yaml string
		want int
	}{
		{"absent", valid, DefaultWorkingHours},
		{"one", "working_hours: 1\n" + valid, 1},
		{"upper limit", "working_hours: " + strconv.Itoa(MaxWorkingHours) + "\n" + valid, MaxWorkingHours},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := parse([]byte(tc.yaml))
			if err != nil || got.WorkingHours != tc.want {
				t.Errorf("want working_hours %d and no error, got %d, %v", tc.want, got.WorkingHours, err)
			}
		})
	}
}

// TestRejectedWorkingHoursFallBack (forsgren#71, #183): zero, a negative
// number, more than 24, a fraction, a float written 8.0 or a word is not
// accepted: 8 is in force, and the rejection names the key and the limit.
func TestRejectedWorkingHoursFallBack(t *testing.T) {
	workingHoursTest := daysTestKey{"working_hours", ErrWorkingHours, func(c Config) int { return c.WorkingHours },
		DefaultWorkingHours, MaxWorkingHours}
	wantDaysRejected(t, workingHoursTest,
		map[string]string{
			"zero":       "0",
			"negative":   "-1",
			"too many":   "25",
			"fraction":   "8.5",
			"float":      "8.0",
			"not number": `"eight"`,
		})
}

// TestWorkingHoursSetSaysWhetherTheKeyIsWritten (forsgren#71, #183): true when
// the file has an accepted working_hours key, false when it is left out or
// not accepted.
func TestWorkingHoursSetSaysWhetherTheKeyIsWritten(t *testing.T) {
	for yaml, want := range map[string]bool{valid: false, "working_hours: 8\n" + valid: true,
		"working_hours: 25\n" + valid: false} {
		got, err := parse([]byte(yaml))
		if err != nil || got.WorkingHoursSet != want {
			t.Errorf("want WorkingHoursSet %v and no error, got %v, %v", want, got.WorkingHoursSet, err)
		}
	}
}
