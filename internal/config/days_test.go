package config

import (
	"errors"
	"strconv"
	"strings"
	"testing"
)

// daysTestKey is one top-level key that is a whole number of days (forsgren#57):
// its name, its refusal, how the Config holds it, its default and its limit.
type daysTestKey struct {
	name     string
	sentinel error
	got      func(Config) int
	def      int
	upper    int
}

var (
	historyDaysTest = daysTestKey{"history_days", ErrHistoryDays, func(c Config) int { return c.HistoryDays }, 365, 1825}
	chunkDaysTest   = daysTestKey{"history_chunk_days", ErrHistoryChunkDays,
		func(c Config) int { return c.HistoryChunkDays }, 100, 365}
)

// wantDaysRead wants the key's default when it is left out, and the value as
// written for 30 and for its upper limit.
func wantDaysRead(t *testing.T, k daysTestKey) {
	t.Helper()
	cases := []struct {
		name string
		yaml string
		want int
	}{
		{"absent", valid, k.def},
		{"thirty", k.name + ": 30\n" + valid, 30},
		{"upper limit", valid + k.name + ": " + strconv.Itoa(k.upper) + "\n", k.upper},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := parse([]byte(tc.yaml))
			if err != nil || k.got(got) != tc.want {
				t.Errorf("want %s %d and no error, got %d, %v", k.name, tc.want, k.got(got), err)
			}
		})
	}
}

// wantDaysRefused wants each value refused with the key's sentinel, a message
// that names the key and its limit.
func wantDaysRefused(t *testing.T, k daysTestKey, values map[string]string) {
	t.Helper()
	for name, value := range values {
		t.Run(name, func(t *testing.T) {
			_, err := parse([]byte(k.name + ": " + value + "\n" + valid))
			wantRefusal(t, err, k.sentinel, k.name, strconv.Itoa(k.upper))
		})
	}
}

// wantRefusal wants err to be sentinel and its message to hold each part.
func wantRefusal(t *testing.T, err, sentinel error, parts ...string) {
	t.Helper()
	if !errors.Is(err, sentinel) {
		t.Fatalf("want %v, got %v", sentinel, err)
	}
	for _, part := range parts {
		if !strings.Contains(err.Error(), part) {
			t.Errorf("want the message to name %q, got %q", part, err)
		}
	}
}
