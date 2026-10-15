package config

import (
	"strings"
	"testing"
)

// TestDoraDaysDefaultsTo30AndReadsEachAllowedValue (forsgren#178): the
// optional top-level dora_days key is 30, 90 or 180; 30 when the key is left
// out or written without a value.
func TestDoraDaysDefaultsTo30AndReadsEachAllowedValue(t *testing.T) {
	cases := []struct {
		name string
		yaml string
		want int
	}{
		{"absent", valid, DefaultDoraDays},
		{"no value", "dora_days:\n" + valid, DefaultDoraDays},
		{"thirty", "dora_days: 30\n" + valid, 30},
		{"ninety", "dora_days: 90\n" + valid, 90},
		{"one hundred eighty", "dora_days: 180\n" + valid, 180},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := parse([]byte(tc.yaml))
			if err != nil || got.DoraDays != tc.want {
				t.Errorf("want dora_days %d and no error, got %d, %v", tc.want, got.DoraDays, err)
			}
		})
	}
}

// TestRejectedDoraDaysFallsBackTo30 (forsgren#178, #183): any other value is
// not accepted: 30 is in force and the rejection names the key and the three
// values.
func TestRejectedDoraDaysFallsBackTo30(t *testing.T) {
	for name, value := range map[string]string{
		"sixty": "60", "zero": "0", "negative": "-30", "a year": "365", "fraction": "30.5",
		"float": "90.0", "quoted": `"90"`, "word": "ninety",
	} {
		t.Run(name, func(t *testing.T) {
			got, err := parse([]byte("dora_days: " + value + "\n" + valid))
			if err != nil || got.DoraDays != DefaultDoraDays {
				t.Fatalf("want dora_days 30 and no error, got %d, %v", got.DoraDays, err)
			}
			wantRejection(t, got.Rejected, ErrDoraDays,
				[4]string{"dora_days", strings.Trim(value, `"`), "use 30, 90 or 180", "30"})
		})
	}
}

// TestDoraDaysLongerThanHistoryDaysFallsBack (forsgren#178, #183): a written
// dora_days the history cannot reach back is not accepted: 30 is in force and
// the reason names both numbers.
func TestDoraDaysLongerThanHistoryDaysFallsBack(t *testing.T) {
	got, err := parse([]byte("dora_days: 180\nhistory_days: 90\n" + valid))
	if err != nil || got.DoraDays != DefaultDoraDays {
		t.Fatalf("want dora_days 30 and no error, got %d, %v", got.DoraDays, err)
	}
	wantRejection(t, got.Rejected, ErrDoraDays, [4]string{"dora_days", "180",
		"history_days is 90, so the history cannot reach back 180 days; " +
			"raise history_days to at least 180 or use a shorter window", "30"})
}

// TestDoraDaysThatFitHistoryDaysLoad (forsgren#178): equal fits, the default
// history of 365 days fits every window, and the default window of 30 fits
// the smallest history_days, 30.
func TestDoraDaysThatFitHistoryDaysLoad(t *testing.T) {
	for name, yaml := range map[string]string{
		"equal":              "dora_days: 90\nhistory_days: 90\n",
		"default history":    "dora_days: 180\n",
		"smallest history":   "history_days: 30\n",
		"unwritten no value": "dora_days:\nhistory_days: 30\n",
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := parse([]byte(yaml + valid)); err != nil {
				t.Errorf("want no error, got %v", err)
			}
		})
	}
}

// TestRejectedHistoryDaysLeavesDoraDaysCheckedAgainstTheDefaultHistory
// (forsgren#183): dora_days is checked against the history_days in force, so
// a history_days that is not accepted (365 in force) does not refuse a window
// the default history reaches, and the other keys are still read.
func TestRejectedHistoryDaysLeavesDoraDaysCheckedAgainstTheDefaultHistory(t *testing.T) {
	got, err := parse([]byte("history_days: 0\ndora_days: 180\nworking_hours: 6\n" + valid))
	if err != nil {
		t.Fatal(err)
	}
	if len(got.Rejected) != 1 || got.Rejected[0].Key != "history_days" {
		t.Errorf("want only history_days rejected, got %v", got.Rejected)
	}
	if got.DoraDays != DoraDays180 {
		t.Errorf("want dora_days 180, got %d", got.DoraDays)
	}
	if got.WorkingHours != 6 {
		t.Errorf("want working_hours 6, got %d", got.WorkingHours)
	}
}

// TestHistoryDaysBelowTheMinimumLeavesTheWindowChecked (forsgren#178): a
// history_days under 30 is not accepted, 365 is in force, so a written window
// is checked against 365 and fits.
func TestHistoryDaysBelowTheMinimumLeavesTheWindowChecked(t *testing.T) {
	got, err := parse([]byte("history_days: 7\ndora_days: 180\n" + valid))
	if err != nil || got.DoraDays != 180 || got.HistoryDays != DefaultHistoryDays {
		t.Fatalf("want history 365, window 180 and no error, got %d, %d, %v", got.HistoryDays, got.DoraDays, err)
	}
	if len(got.Rejected) != 1 || got.Rejected[0].Key != "history_days" {
		t.Errorf("want only history_days rejected, got %v", got.Rejected)
	}
}
