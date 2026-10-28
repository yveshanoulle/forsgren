package page

import (
	"testing"

	"github.com/yveshanoulle/forsgren/internal/config"
)

// separatorConflict is the reason both separator rows give when both are the
// comma (forsgren#536, decision #537 A).
const separatorConflict = "thousands_separator comma and decimal_separator comma are both the mark \",\"; " +
	"use different marks; both separators revert to their defaults, narrow_space and point"

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
		case "thousands_separator", "decimal_separator":
			data.Settings[i].Written = "comma"
			data.Settings[i].Reason = separatorConflict
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

// TestSettingsPageShowsBothRowsOfASeparatorConflict (forsgren#536, decision
// #537 A): each of the two separator rows says its value is not accepted, the
// conflict as the reason, and the default in use.
func TestSettingsPageShowsBothRowsOfASeparatorConflict(t *testing.T) {
	html := rendered(t, "settings.html", withRejected("weekly"))
	reason := "are both the mark &#34;,&#34;; use different marks; both separators revert to their defaults, " +
		"narrow_space and point. Using the default <span class=\"default-in-force\">"
	row := func(key, def, possible string) string {
		return `<th scope="row">` + key + `</th>
            <td><span class="written">comma</span> is not accepted: thousands_separator comma and ` +
			`decimal_separator comma ` + reason + def + `</span>.</td>
            <td>` + possible + `</td>`
	}
	wantAll(t, "settings.html", html, row("thousands_separator", "narrow_space", "narrow_space, comma, period, none"),
		row("decimal_separator", "point", "point, comma"))
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
