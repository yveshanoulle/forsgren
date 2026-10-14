package config

import "testing"

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

// TestParseRefusesANonBooleanPageKey (forsgren#159): any value that is not the
// YAML boolean true or false is refused, naming the key and the valid values.
func TestParseRefusesANonBooleanPageKey(t *testing.T) {
	checkRefusals(t, []refusal{
		{"issues yes", "issues_page: yes\n" + valid, ErrIssuesPage, `invalid issues_page "yes": use true or false`},
		{"days quoted", "days_page: \"true\"\n" + valid, ErrDaysPage, `invalid days_page "true": use true or false`},
		{"days number", "days_page: 0\n" + valid, ErrDaysPage, `invalid days_page "0": use true or false`},
	})
}
