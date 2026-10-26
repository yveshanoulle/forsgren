package page

import (
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/config"
)

// TestPossibleValuesAreExactlyWhatCheckConfigAccepts (forsgren#141): for every
// optional key, each value the settings page lists is accepted by the config
// loader, which check-config runs, and the values just outside the list are
// refused or, for a key with a default, rejected (forsgren#183), so the page
// cannot drift from what the loader accepts. Proven by mutation: a limit of
// the page that drifted by one.
func TestPossibleValuesAreExactlyWhatCheckConfigAccepts(t *testing.T) {
	for _, setting := range (config.Config{}).Settings() {
		possible := possibleOf(setting.Key)
		if possible == "" {
			t.Fatalf("want possible values for %s on the settings page, got none", setting.Key)
		}
		if setting.Key == "same_developer" {
			wantLoads(t, setting.Key, "[[maintainer, assistant-account]]", true)
			wantLoads(t, setting.Key, "[[maintainer]]", false)
			continue
		}
		accepted, refused := probesOf(t, possible)
		for _, value := range accepted {
			wantLoads(t, setting.Key, value, true)
		}
		for _, value := range refused {
			wantLoads(t, setting.Key, value, false)
		}
	}
}

// probesOf are the values a column of possible values promises are accepted
// and the ones next to it that must be refused: "a, b, c" promises each name
// and refuses a name it does not list; "1 to 9" promises 1 and 9 and refuses 0
// and 10.
func probesOf(t *testing.T, possible string) (accepted, refused []string) {
	t.Helper()
	low, high, isRange := strings.Cut(possible, " to ")
	if !isRange {
		return strings.Split(possible, ", "), []string{"not-listed"}
	}
	first, errFirst := strconv.Atoi(low)
	last, errLast := strconv.Atoi(high)
	if errFirst != nil || errLast != nil {
		t.Fatalf("want a range like 1 to 9, got %q", possible)
	}
	return []string{low, high}, []string{strconv.Itoa(first - 1), strconv.Itoa(last + 1)}
}

// companions are the line a key needs beside it for the file to be valid:
// auto_update needs its level, and a level needs auto_update on.
var companions = map[string]string{
	"auto_update":       "auto_update_level: patch\n",
	"auto_update_level": "auto_update: true\n",
}

// wantLoads fails t unless a config file that sets key to value loads exactly
// when ok says it should.
func wantLoads(t *testing.T, key, value string, ok bool) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "forsgren.config.yml")
	content := fmt.Sprintf("version: 1\n%s: %s\n%sprojects: []\n", key, value, companions[key])
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	cfg, err := config.Load(path)
	accepted := err == nil && !slices.ContainsFunc(cfg.Rejected, func(r config.Rejection) bool { return r.Key == key })
	if accepted != ok {
		t.Errorf("%s: %s: want the config loader to accept it: %v, got %v (error %v, rejected %v)",
			key, value, ok, accepted, err, cfg.Rejected)
	}
}

// TestSettingsPageDefaultColumnShowsTheDefaultValue (forsgren#169): the
// Default column holds the key's default value, not whether the file sets the
// key: a key the file sets to another value and one it leaves out both show
// their default.
func TestSettingsPageDefaultColumnShowsTheDefaultValue(t *testing.T) {
	data := withTwoSettings()
	wantAll(t, "settings.html", rendered(t, "settings.html", data),
		`<th scope="row">view</th>
            <td>numbers</td>
            <td>standard, numbers, scoring</td>
            <td>standard</td>`,
		`<th scope="row">history_days</th>
            <td>365 (not set)</td>
            <td>30 to 1825</td>
            <td>365</td>`,
	)
	wantNone(t, "settings.html", rendered(t, "settings.html", data), "<td>True</td>", "<td>False</td>")
}

// TestSettingsPageMarksAnUnsetKey (forsgren#169, decision 2 on #189): the
// Current value of a key the file does not set reads `<value> (not set)`; a
// key the file sets is bare, even when it equals the default; a key that is
// not accepted keeps its sentence, with no marker.
func TestSettingsPageMarksAnUnsetKey(t *testing.T) {
	data := withTwoSettings()
	data.Settings = append(data.Settings,
		config.Setting{Key: "working_hours", Value: "8", Default: "8", Set: true},
		config.Setting{Key: "dora_days", Value: "30", Default: "30", Written: "60", Reason: "use 30, 90 or 180"})
	html := rendered(t, "settings.html", data)
	wantAll(t, "settings.html", html,
		`<th scope="row">view</th>
            <td>numbers</td>`,
		`<th scope="row">history_days</th>
            <td>365 (not set)</td>`,
		`<th scope="row">working_hours</th>
            <td>8</td>`,
		`<span class="default-in-force">30</span>.</td>`)
	wantNone(t, "settings.html", html, "30 (not set)", "8 (not set)", "</span> (not set)")
}

// TestEveryValueTheConfigAcceptsIsListedOnTheSettingsPage (forsgren#79, #200):
// the other half of the drift test. For each key that takes a fixed set of
// values, every value the config package accepts (config.Accepted, the set its
// own loader checks against) is listed in the Possible values column, so a
// value cannot be accepted without showing on the page. A numeric key has no
// set; its range is held by the probes of the test above.
func TestEveryValueTheConfigAcceptsIsListedOnTheSettingsPage(t *testing.T) {
	enumerated := []string{"view", "auto_update", "auto_update_level", "dora_days", "issues_page", "days_page",
		"numbers_scoring_page", "history_page", "tbd_page", "tbd_figures", "tbd_time_to_main", "tbd_pr_lead_time",
		"tbd_bot_pr_lead_time", "sub_rows"}
	for _, key := range enumerated {
		wantListed(t, key, config.Accepted(key))
	}
	for _, setting := range (config.Config{}).Settings() {
		if config.Accepted(setting.Key) != nil && !slices.Contains(enumerated, setting.Key) {
			t.Errorf("%s: want the key in the enumerated keys of this test", setting.Key)
		}
	}
}

// wantListed fails t unless accepted is not empty and every value in it is
// listed in the Possible values of the key.
func wantListed(t *testing.T, key string, accepted []string) {
	t.Helper()
	if len(accepted) == 0 {
		t.Errorf("%s: want the config to say which values it accepts, got none", key)
	}
	listed := strings.Split(possibleOf(key), ", ")
	for _, value := range accepted {
		if !slices.Contains(listed, value) {
			t.Errorf("%s: want the settings page to list %q, which the config accepts, got %v", key, value, listed)
		}
	}
}

// TestSettingsPageListsTheSwitches (forsgren#482, decisions #480, #481, #488):
// the four switches are rows of the settings page, each with the Possible
// values true and false and the default true, not set.
func TestSettingsPageListsTheSwitches(t *testing.T) {
	data := Placeholder("1.0.0")
	data.Settings = (config.Config{}).Settings()
	html := rendered(t, "settings.html", data)
	for _, key := range []string{"tbd_time_to_main", "tbd_pr_lead_time", "tbd_bot_pr_lead_time", "sub_rows"} {
		wantAll(t, "settings.html", html, `<th scope="row">`+key+`</th>
            <td>true (not set)</td>
            <td>true, false</td>
            <td>true</td>`)
	}
}
