package page

import (
	"testing"

	"github.com/yveshanoulle/forsgren/internal/config"
)

// withTwoSettings is the placeholder with one setting the config sets, view:
// numbers, and one it leaves at its default, history_days: 365.
func withTwoSettings() Data {
	data := Placeholder(testVersion)
	data.Settings = []config.Setting{{Key: "view", Value: "numbers", Default: "standard", Set: true},
		{Key: "history_days", Value: "365", Default: "365"}}
	return data
}

// TestSettingsPageIsATableOfParameterValuePossibleValuesAndDefault
// (forsgren#74, #84, #141): the settings page tabulates each setting under
// Parameter, Current value, Possible values and Default; Default is the key's
// default value (forsgren#169).
func TestSettingsPageIsATableOfParameterValuePossibleValuesAndDefault(t *testing.T) {
	data := withTwoSettings()
	wantAll(t, "settings.html", rendered(t, "settings.html", data),
		`<th scope="col">Parameter</th>
            <th scope="col">Current value</th>
            <th scope="col">Possible values</th>
            <th scope="col">Default</th>`,
		`<th scope="row">view</th>
            <td>numbers</td>
            <td>standard, numbers, scoring</td>
            <td>standard</td>`,
		`<th scope="row">history_days</th>
            <td>365 (not set)</td>
            <td>30 to 1825</td>
            <td>365</td>`,
	)
}

// TestSettingsPageHasNoNoteOnTheAutoUpdateLevel (forsgren#157): the possible
// values of auto_update_level are exactly patch, minor and major; the level is
// optional, so the cell carries no rule.
func TestSettingsPageHasNoNoteOnTheAutoUpdateLevel(t *testing.T) {
	data := calculated()
	data.Settings = append(config.Config{}.Settings(), config.Config{}.RepositorySettings()...)
	html := rendered(t, "settings.html", data)
	wantAll(t, "settings.html", html, "<td>patch, minor, major</td>")
	wantNone(t, "settings.html", html, "required when auto_update")
}
