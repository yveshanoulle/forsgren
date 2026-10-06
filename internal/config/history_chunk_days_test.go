package config

import "testing"

// TestHistoryChunkDaysIsRead (forsgren#57): the optional top-level
// history_chunk_days key, a whole number of days from 1 to 365; 100 when the
// key is left out.
func TestHistoryChunkDaysIsRead(t *testing.T) {
	wantDaysRead(t, chunkDaysTest)
}

// TestParseRefusesAnInvalidHistoryChunkDays (forsgren#57): a non-integer,
// zero, a negative number or more than 365 is refused, naming the key and
// the limit.
func TestParseRefusesAnInvalidHistoryChunkDays(t *testing.T) {
	wantDaysRefused(t, chunkDaysTest, map[string]string{
		"zero":       "0",
		"negative":   "-1",
		"too many":   "366",
		"not number": `"a quarter"`,
	})
}
