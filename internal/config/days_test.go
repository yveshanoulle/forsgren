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
	lower    int
}

var (
	historyDaysTest = daysTestKey{"history_days", ErrHistoryDays, func(c Config) int { return c.HistoryDays },
		365, 1825, 30}
	chunkDaysTest = daysTestKey{"history_chunk_days", ErrHistoryChunkDays,
		func(c Config) int { return c.HistoryChunkDays }, 100, 365, 1}
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
		{"lower limit", k.name + ": " + strconv.Itoa(k.lower) + "\n" + valid, k.lower},
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

// wantDaysRejected wants each value not accepted: the key falls back to its
// default and counts as not written, and the one rejection names the key, the
// value as written, the limit and the default (forsgren#183).
func wantDaysRejected(t *testing.T, k daysTestKey, values map[string]string) {
	t.Helper()
	unit := map[string]string{"working_hours": "hours"}[k.name]
	if unit == "" {
		unit = "days"
	}
	for name, value := range values {
		t.Run(name, func(t *testing.T) {
			got, err := parse([]byte(k.name + ": " + value + "\n" + valid))
			if err != nil || k.got(got) != k.def || got.written[k.name] {
				t.Fatalf("want %s %d not written and no error, got %d, %v, %v", k.name, k.def, k.got(got), got.written, err)
			}
			wantRejection(t, got.Rejected, k.sentinel, [4]string{k.name, strings.Trim(value, `"`),
				"use a whole number of " + unit + " from " + strconv.Itoa(k.lower) + " to " + strconv.Itoa(k.upper),
				strconv.Itoa(k.def)})
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
