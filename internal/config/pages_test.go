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
		wantIssues, wantDays bool
	}{
		{"absent", valid, true, false},
		{"both on", "issues_page: true\ndays_page: true\n" + valid, true, true},
		{"both off", "issues_page: false\ndays_page: false\n" + valid, false, false},
		{"issues off", valid + "issues_page: false\n", false, false},
		{"days on", "days_page: true\n" + valid, true, true},
		{"no value", "issues_page:\ndays_page: null\n" + valid, true, false},
	}
	for _, tc := range cases {
		got, err := parse([]byte(tc.file))
		if err != nil || got.IssuesPage != tc.wantIssues || got.DaysPage != tc.wantDays {
			t.Errorf("%s: want issues_page %v, days_page %v and no error, got %v, %v, %v",
				tc.name, tc.wantIssues, tc.wantDays, got.IssuesPage, got.DaysPage, err)
		}
	}
}

// TestNumbersScoringPageIsRead (forsgren#55): the optional numbers_scoring_page
// key, as written; the page is off when the key is left out or has no value.
func TestNumbersScoringPageIsRead(t *testing.T) {
	cases := []struct {
		name, file string
		want       bool
	}{
		{"absent", valid, false},
		{"on", "numbers_scoring_page: true\n" + valid, true},
		{"off", "numbers_scoring_page: false\n" + valid, false},
		{"after the projects", valid + "numbers_scoring_page: true\n", true},
		{"no value", "numbers_scoring_page:\n" + valid, false},
	}
	for _, tc := range cases {
		got, err := parse([]byte(tc.file))
		if err != nil || got.NumbersScoringPage != tc.want {
			t.Errorf("%s: want numbers_scoring_page %v and no error, got %v, %v", tc.name, tc.want, got.NumbersScoringPage, err)
		}
	}
}

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
		wantIssues, wantDays bool
	}{
		{"issues yes", "issues_page: yes\n" + valid, ErrIssuesPage,
			[4]string{"issues_page", "yes", "use true or false", "true"}, true, false},
		{"days quoted", "days_page: \"true\"\n" + valid, ErrDaysPage,
			[4]string{"days_page", "true", "use true or false", "false"}, true, false},
		{"days number", "days_page: 0\n" + valid, ErrDaysPage,
			[4]string{"days_page", "0", "use true or false", "false"}, true, false},
		{"the other key is kept", "issues_page: false\ndays_page: yes\n" + valid, ErrDaysPage,
			[4]string{"days_page", "yes", "use true or false", "false"}, false, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := parse([]byte(tc.file))
			if err != nil || got.IssuesPage != tc.wantIssues || got.DaysPage != tc.wantDays || got.written[tc.want[0]] {
				t.Fatalf("want issues_page %v, days_page %v, %s not written and no error, got %v, %v, %v, %v",
					tc.wantIssues, tc.wantDays, tc.want[0], got.IssuesPage, got.DaysPage, got.written, err)
			}
			wantRejection(t, got.Rejected, tc.sentinel, tc.want)
		})
	}
}

// TestRejectedNumbersScoringPageFallsBack (forsgren#55, #183): a value that is
// not the YAML boolean true or false is not accepted: the page stays off, the
// key counts as not written, and the rejection names the key and the valid
// values.
func TestRejectedNumbersScoringPageFallsBack(t *testing.T) {
	for written, line := range map[string]string{"yes": "yes", "true": "\"true\"", "1": "1"} {
		got, err := parse([]byte("numbers_scoring_page: " + line + "\n" + valid))
		if err != nil || got.NumbersScoringPage || got.written["numbers_scoring_page"] {
			t.Errorf("%s: want the page off and the key not written, got %v, %v, %v", written,
				got.NumbersScoringPage, got.written, err)
		}
		wantRejection(t, got.Rejected, ErrNumbersScoringPage,
			[4]string{"numbers_scoring_page", written, "use true or false", "false"})
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

// TestHistoryPageDefaultsToTrueAndRejectsOtherValues (forsgren#68): the
// optional history_page key is on when it is left out or has no value, as
// written otherwise; a value that is not the YAML boolean true or false is
// not accepted: the page stays on, the key counts as not written, and the
// rejection names the key, the valid values and the default true.
func TestHistoryPageDefaultsToTrueAndRejectsOtherValues(t *testing.T) {
	cases := []struct {
		name, file, rejected string
		want                 bool
	}{
		{"absent", valid, "", true},
		{"on", "history_page: true\n" + valid, "", true},
		{"off", "history_page: false\n" + valid, "", false},
		{"after the projects", valid + "history_page: false\n", "", false},
		{"no value", "history_page:\n" + valid, "", true},
		{"yes", "history_page: yes\n" + valid, "yes", true},
		{"quoted", "history_page: \"false\"\n" + valid, "false", true},
		{"a number", "history_page: 0\n" + valid, "0", true},
	}
	for _, tc := range cases {
		got, err := parse([]byte(tc.file))
		if err != nil || got.HistoryPage != tc.want {
			t.Errorf("%s: want history_page %v and no error, got %v, %v", tc.name, tc.want, got.HistoryPage, err)
		}
		if tc.rejected != "" {
			wantRejection(t, got.Rejected, ErrHistoryPage,
				[4]string{"history_page", tc.rejected, "use true or false", "true"})
		}
	}
}
