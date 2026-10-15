package config

import "testing"

// TestHistoryDaysIsRead (forsgren#57): the optional top-level history_days
// key, a whole number of days from 30 to 1825; 365 when the key is left out.
func TestHistoryDaysIsRead(t *testing.T) {
	wantDaysRead(t, historyDaysTest)
}

// TestRejectedHistoryDaysFallsBack (forsgren#57): a non-integer, zero, a
// negative number, 29 or less, or more than 1825 is not accepted: the default is in force, and the
// rejection names the key and the limit (forsgren#183).
func TestRejectedHistoryDaysFallsBack(t *testing.T) {
	wantDaysRejected(t, historyDaysTest, map[string]string{
		"zero":       "0",
		"negative":   "-1",
		"below 30":   "29",
		"one":        "1",
		"too many":   "1826",
		"not number": `"a year"`,
	})
}
