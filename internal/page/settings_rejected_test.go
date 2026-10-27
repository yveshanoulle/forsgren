package page

import (
	"testing"

	"github.com/yveshanoulle/forsgren/internal/config"
)

// withRejected is the calculated page with the settings of a config whose
// history_days is 0 and whose view is written as written (forsgren#183).
func withRejected(view string) Data {
	data := calculated()
	data.Settings = append(config.Config{}.Settings(), config.Config{}.RepositorySettings()...)
	for i := range data.Settings {
		switch data.Settings[i].Key {
		case "history_days":
			data.Settings[i].Written = "0"
			data.Settings[i].Reason = "use a whole number of days from 30 to 1825"
		case "view":
			data.Settings[i].Written = view
			data.Settings[i].Reason = "use standard, numbers or scoring"
		}
	}
	return data
}

// TestSettingsPageSaysARejectedValue (forsgren#183): the row of a setting
// that is not accepted says, in plain text, the value as written, that it is
// not accepted and why, and the default in use; the Default column shows that default.
func TestSettingsPageSaysARejectedValue(t *testing.T) {
	wantAll(t, "settings.html", rendered(t, "settings.html", withRejected("weekly")),
		`<tr class="not-accepted">
            <th scope="row">history_days</th>
            <td><span class="written">0</span> is not accepted: use a whole number of days from 30 to 1825. `+
			`Using the default <span class="default-in-force">365</span>.</td>
            <td>30 to 1825</td>
            <td>365</td>
          </tr>`,
		`<tr>
            <th scope="row">auto_update</th>`)
}

// TestSettingsPageShowsAWrittenValueAsText (forsgren#183): the value as written
// is file text, so markup in it shows as text; an empty one is named.
func TestSettingsPageShowsAWrittenValueAsText(t *testing.T) {
	wantAll(t, "settings.html", rendered(t, "settings.html", withRejected("<b>&")),
		`<span class="written">&lt;b&gt;&amp;</span> is not accepted`)
	wantAll(t, "settings.html", rendered(t, "settings.html", withRejected("")),
		`<span class="written">(empty)</span> is not accepted`)
}

// TestSettingsPageWithRejectedSettingsMatchesGolden (forsgren#183).
func TestSettingsPageWithRejectedSettingsMatchesGolden(t *testing.T) {
	checkPageGolden(t, "settings.html", "testdata/settings.rejected.golden.html", withRejected("weekly"))
}
