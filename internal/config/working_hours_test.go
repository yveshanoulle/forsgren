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

// TestParseRefusesInvalidWorkingHours (forsgren#71): zero, a negative number,
// more than 24, a fraction, a float written 8.0 or a word is refused, naming
// the key and the limit.
func TestParseRefusesInvalidWorkingHours(t *testing.T) {
	wantDaysRefused(t, daysTestKey{name: "working_hours", sentinel: ErrWorkingHours, upper: MaxWorkingHours},
		map[string]string{
			"zero":       "0",
			"negative":   "-1",
			"too many":   "25",
			"fraction":   "8.5",
			"float":      "8.0",
			"not number": `"eight"`,
		})
}

// TestWorkingHoursSetSaysWhetherTheKeyIsWritten (forsgren#71): true when the
// file has a working_hours key, false when it is left out.
func TestWorkingHoursSetSaysWhetherTheKeyIsWritten(t *testing.T) {
	for yaml, want := range map[string]bool{valid: false, "working_hours: 8\n" + valid: true} {
		got, err := parse([]byte(yaml))
		if err != nil || got.WorkingHoursSet != want {
			t.Errorf("want WorkingHoursSet %v and no error, got %v, %v", want, got.WorkingHoursSet, err)
		}
	}
}
