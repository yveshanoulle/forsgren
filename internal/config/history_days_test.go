package config

import "testing"

// TestHistoryDaysIsRead (forsgren#57): the optional top-level history_days
// key, a whole number of days from 1 to 1825; 365 when the key is left out.
func TestHistoryDaysIsRead(t *testing.T) {
	wantDaysRead(t, historyDaysTest)
}

// TestParseRefusesAnInvalidHistoryDays (forsgren#57): a non-integer, zero, a
// negative number or more than 1825 is refused, naming the key and the limit.
func TestParseRefusesAnInvalidHistoryDays(t *testing.T) {
	wantDaysRefused(t, historyDaysTest, map[string]string{
		"zero":       "0",
		"negative":   "-1",
		"too many":   "1826",
		"not number": `"a year"`,
	})
}
