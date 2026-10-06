package config

import (
	"errors"
	"strings"
	"testing"
)

// TestHistoryChunkDaysIsRead (forsgren#57): the optional top-level
// history_chunk_days key, a whole number of days from 1 to 365; 100 when the
// key is left out.
func TestHistoryChunkDaysIsRead(t *testing.T) {
	cases := []struct {
		name string
		yaml string
		want int
	}{
		{"absent", valid, 100},
		{"thirty", "history_chunk_days: 30\n" + valid, 30},
		{"upper limit", valid + "history_chunk_days: 365\n", 365},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := parse([]byte(tc.yaml))
			if err != nil || got.HistoryChunkDays != tc.want {
				t.Errorf("want history_chunk_days %d and no error, got %d, %v", tc.want, got.HistoryChunkDays, err)
			}
		})
	}
}

// TestParseRefusesAnInvalidHistoryChunkDays (forsgren#57): a non-integer,
// zero, a negative number or more than 365 is refused, naming the key and
// the limit.
func TestParseRefusesAnInvalidHistoryChunkDays(t *testing.T) {
	values := map[string]string{
		"zero":       "0",
		"negative":   "-1",
		"too many":   "366",
		"not number": `"a quarter"`,
	}
	for name, value := range values {
		t.Run(name, func(t *testing.T) {
			_, err := parse([]byte("history_chunk_days: " + value + "\n" + valid))
			wantChunkNamed(t, err, "history_chunk_days", "365")
		})
	}
}

// wantChunkNamed wants err to be ErrHistoryChunkDays and its message to hold
// each part.
func wantChunkNamed(t *testing.T, err error, parts ...string) {
	t.Helper()
	if !errors.Is(err, ErrHistoryChunkDays) {
		t.Fatalf("want %v, got %v", ErrHistoryChunkDays, err)
	}
	for _, part := range parts {
		if !strings.Contains(err.Error(), part) {
			t.Errorf("want the message to name %q, got %q", part, err)
		}
	}
}
