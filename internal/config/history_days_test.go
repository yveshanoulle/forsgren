package config

import (
	"errors"
	"strings"
	"testing"
)

// TestHistoryDaysIsRead (forsgren#57): the optional top-level history_days
// key, a whole number of days from 1 to 1825; 365 when the key is left out.
func TestHistoryDaysIsRead(t *testing.T) {
	cases := []struct {
		name string
		yaml string
		want int
	}{
		{"absent", valid, 365},
		{"thirty", "history_days: 30\n" + valid, 30},
		{"upper limit", valid + "history_days: 1825\n", 1825},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := parse([]byte(tc.yaml))
			if err != nil || got.HistoryDays != tc.want {
				t.Errorf("want history_days %d and no error, got %d, %v", tc.want, got.HistoryDays, err)
			}
		})
	}
}

// TestParseRefusesAnInvalidHistoryDays (forsgren#57): a non-integer, zero, a
// negative number or more than 1825 is refused, naming the key and the limit.
func TestParseRefusesAnInvalidHistoryDays(t *testing.T) {
	values := map[string]string{
		"zero":       "0",
		"negative":   "-1",
		"too many":   "1826",
		"not number": `"a year"`,
	}
	for name, value := range values {
		t.Run(name, func(t *testing.T) {
			_, err := parse([]byte("history_days: " + value + "\n" + valid))
			wantNamed(t, err, "history_days", "1825")
		})
	}
}

// wantNamed wants err to be ErrHistoryDays and its message to hold each part.
func wantNamed(t *testing.T, err error, parts ...string) {
	t.Helper()
	if !errors.Is(err, ErrHistoryDays) {
		t.Fatalf("want %v, got %v", ErrHistoryDays, err)
	}
	for _, part := range parts {
		if !strings.Contains(err.Error(), part) {
			t.Errorf("want the message to name %q, got %q", part, err)
		}
	}
}
