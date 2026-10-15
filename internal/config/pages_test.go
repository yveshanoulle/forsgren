package config

import (
	"slices"
	"testing"
)

// TestIssuesAndDaysPagesAreRead (forsgren#159): the optional issues_page and
// days_page keys, as written; the issues page is on and the days page off
// when a key is left out or has no value.
func TestIssuesAndDaysPagesAreRead(t *testing.T) {
	cases := []struct {
		name, file           string
		wantIssues, wantDays PageMode
	}{
		{"absent", valid, PageOn, PageOff},
		{"both on", "issues_page: true\ndays_page: true\n" + valid, PageOn, PageOn},
		{"both off", "issues_page: false\ndays_page: false\n" + valid, PageOff, PageOff},
		{"issues off", valid + "issues_page: false\n", PageOff, PageOff},
		{"days on", "days_page: true\n" + valid, PageOn, PageOn},
		{"no value", "issues_page:\ndays_page: null\n" + valid, PageOn, PageOff},
	}
	for _, tc := range cases {
		got, err := parse([]byte(tc.file))
		if err != nil || issuesAndDays(got) != [2]PageMode{tc.wantIssues, tc.wantDays} {
			t.Errorf("%s: want issues_page %v, days_page %v and no error, got %v, %v, %v",
				tc.name, tc.wantIssues, tc.wantDays, got.IssuesPage, got.DaysPage, err)
		}
	}
}

// TestNumbersScoringPageIsRead (forsgren#55): the optional numbers_scoring_page
// key, as written; the page is unlisted when the key is left out or has no value.
func TestNumbersScoringPageIsRead(t *testing.T) {
	cases := []struct {
		name, file string
		want       PageMode
	}{
		{"absent", valid, PageUnlisted},
		{"on", "numbers_scoring_page: true\n" + valid, PageOn},
		{"off", "numbers_scoring_page: false\n" + valid, PageOff},
		{"after the projects", valid + "numbers_scoring_page: true\n", PageOn},
		{"no value", "numbers_scoring_page:\n" + valid, PageUnlisted},
	}
	for _, tc := range cases {
		got, err := parse([]byte(tc.file))
		if err != nil || got.NumbersScoringPage != tc.want {
			t.Errorf("%s: want numbers_scoring_page %v and no error, got %v, %v", tc.name, tc.want, got.NumbersScoringPage, err)
		}
	}
}

// issuesAndDays are the config's issues_page and days_page, in that order.
func issuesAndDays(cfg Config) [2]PageMode { return [2]PageMode{cfg.IssuesPage, cfg.DaysPage} }

// TestRejectedPageKeyFallsBack (forsgren#159, #183): any value that is not the
// YAML boolean true or false is not accepted: the key's default is in force
// (issues page on, days page off) and the key counts as not written; the other
// page key keeps its own value, and the rejection names the key and the
// valid values.
func TestRejectedPageKeyFallsBack(t *testing.T) {
	cases := []struct {
		name, file           string
		sentinel             error
		want                 [4]string
		wantIssues, wantDays PageMode
	}{
		{"issues yes", "issues_page: yes\n" + valid, ErrIssuesPage,
			[4]string{"issues_page", "yes", "use true, unlisted or false", "true"}, PageOn, PageOff},
		{"days quoted", "days_page: \"true\"\n" + valid, ErrDaysPage,
			[4]string{"days_page", "true", "use true, unlisted or false", "false"}, PageOn, PageOff},
		{"days number", "days_page: 0\n" + valid, ErrDaysPage,
			[4]string{"days_page", "0", "use true, unlisted or false", "false"}, PageOn, PageOff},
		{"the other key is kept", "issues_page: false\ndays_page: yes\n" + valid, ErrDaysPage,
			[4]string{"days_page", "yes", "use true, unlisted or false", "false"}, PageOff, PageOff},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := parse([]byte(tc.file))
			if err != nil || got.written[tc.want[0]] {
				t.Fatalf("want %s not written and no error, got %v, %v", tc.want[0], got.written, err)
			}
			if issuesAndDays(got) != [2]PageMode{tc.wantIssues, tc.wantDays} {
				t.Fatalf("want issues_page %v, days_page %v, got %v, %v",
					tc.wantIssues, tc.wantDays, got.IssuesPage, got.DaysPage)
			}
			wantRejection(t, got.Rejected, tc.sentinel, tc.want)
		})
	}
}

// TestRejectedNumbersScoringPageFallsBack (forsgren#55, #183): a value that is
// not the YAML boolean true or false is not accepted: the page stays unlisted, the
// key counts as not written, and the rejection names the key and the valid
// values.
func TestRejectedNumbersScoringPageFallsBack(t *testing.T) {
	for written, line := range map[string]string{"yes": "yes", "true": "\"true\"", "1": "1"} {
		got, err := parse([]byte("numbers_scoring_page: " + line + "\n" + valid))
		if err != nil {
			t.Fatalf("%s: %v", written, err)
		}
		if got.NumbersScoringPage != PageUnlisted || got.written["numbers_scoring_page"] {
			t.Errorf("%s: want the page off and the key not written, got %v, %v", written,
				got.NumbersScoringPage, got.written)
		}
		wantRejection(t, got.Rejected, ErrNumbersScoringPage,
			[4]string{"numbers_scoring_page", written, "use true, unlisted or false", "unlisted"})
	}
}

// TestRejectedNumbersScoringPageIsListedLast (forsgren#55, #183): its
// rejection comes after the other settings' in the order of the settings page.
func TestRejectedNumbersScoringPageIsListedLast(t *testing.T) {
	got, err := parse([]byte("numbers_scoring_page: yes\ndays_page: yes\nview: weekly\n" + valid))
	if err != nil {
		t.Fatal(err)
	}
	var keys []string
	for _, r := range got.Rejected {
		keys = append(keys, r.Key)
	}
	if want := []string{"view", "days_page", "numbers_scoring_page"}; !slices.Equal(keys, want) {
		t.Errorf("want rejections %v, got %v", want, keys)
	}
}

// TestHistoryPageIsUnlistedByDefaultAndRejectsOtherValues (forsgren#68, #199,
// #200): the optional history_page key is unlisted when it is left out or has
// no value, as numbers_scoring_page is, and as written otherwise; a value that
// is not true, unlisted or false is not accepted: the page stays unlisted, the
// key counts as not written, and the rejection names the key, the valid values
// and the default unlisted.
func TestHistoryPageIsUnlistedByDefaultAndRejectsOtherValues(t *testing.T) {
	cases := []struct {
		name, file, rejected string
		want                 PageMode
	}{
		{"absent", valid, "", PageUnlisted},
		{"on", "history_page: true\n" + valid, "", PageOn},
		{"off", "history_page: false\n" + valid, "", PageOff},
		{"after the projects", valid + "history_page: true\n", "", PageOn},
		{"no value", "history_page:\n" + valid, "", PageUnlisted},
		{"yes", "history_page: yes\n" + valid, "yes", PageUnlisted},
		{"quoted", "history_page: \"true\"\n" + valid, "true", PageUnlisted},
		{"a number", "history_page: 1\n" + valid, "1", PageUnlisted},
		{"quoted unlisted", "history_page: \"unlisted\"\n" + valid, "unlisted", PageUnlisted},
	}
	for _, tc := range cases {
		got, err := parse([]byte(tc.file))
		if err != nil || got.HistoryPage != tc.want {
			t.Errorf("%s: want history_page %v and no error, got %v, %v", tc.name, tc.want, got.HistoryPage, err)
		}
		if tc.rejected != "" {
			wantRejection(t, got.Rejected, ErrHistoryPage,
				[4]string{"history_page", tc.rejected, "use true, unlisted or false", "unlisted"})
		}
	}
}

// pageModeOf is the PageMode the config holds for the page key.
func pageModeOf(cfg Config, key string) PageMode {
	return map[string]PageMode{"issues_page": cfg.IssuesPage, "days_page": cfg.DaysPage,
		"numbers_scoring_page": cfg.NumbersScoringPage, "history_page": cfg.HistoryPage}[key]
}

// TestEveryPageKeyReadsUnlisted (forsgren#200): the literal unlisted is a value
// of each of the four page keys, read as PageUnlisted, written, and not
// rejected: the page is generated without a menu entry.
func TestEveryPageKeyReadsUnlisted(t *testing.T) {
	for _, key := range []string{"issues_page", "days_page", "numbers_scoring_page", "history_page"} {
		t.Run(key, func(t *testing.T) {
			got, err := parse([]byte(key + ": unlisted\n" + valid))
			if err != nil || len(got.Rejected) != 0 {
				t.Fatalf("want nothing rejected and no error, got %v, %v", got.Rejected, err)
			}
			if mode := pageModeOf(got, key); mode != PageUnlisted || !got.written[key] {
				t.Errorf("want %s unlisted and written, got %q, written %v", key, mode, got.written[key])
			}
		})
	}
}

// TestAcceptedIsWhatTheLoaderTakes (forsgren#79, #200): every value Accepted
// names for a key loads without a rejection, and a key that takes a number
// names none; the settings page is held to list the same set.
func TestAcceptedIsWhatTheLoaderTakes(t *testing.T) {
	for _, setting := range (Config{}).Settings() {
		for _, value := range Accepted(setting.Key) {
			wantAcceptedValue(t, setting.Key, value)
		}
	}
	for _, key := range []string{"history_days", "history_chunk_days", "working_hours"} {
		if got := Accepted(key); got != nil {
			t.Errorf("%s: want no fixed set for a number, got %v", key, got)
		}
	}
	if got := Accepted("dora_days"); !slices.Equal(got, []string{"30", "90", "180"}) {
		t.Errorf("want the dora windows 30, 90, 180, got %v", got)
	}
}

// wantAcceptedValue fails t unless a file that sets key to value loads with
// no rejection; auto_update and its level need each other.
func wantAcceptedValue(t *testing.T, key, value string) {
	t.Helper()
	companions := map[string]string{"auto_update": "auto_update_level: patch\n",
		"auto_update_level": "auto_update: true\n"}
	got, err := parse([]byte(key + ": " + value + "\n" + companions[key] + valid))
	if err != nil || len(got.Rejected) != 0 {
		t.Errorf("%s: want %s accepted, got %v, %v", key, value, got.Rejected, err)
	}
}
