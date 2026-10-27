package main

import (
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/config"
)

// weekModePage is the Week page for wantMode: its file, its menu address.
var weekModePage = modePage{"week_page", "week.html", "week.html", config.PageOn}

// TestRenderHandlesWeekPageByItsSwitch (forsgren#531, step 3, decision #533 A):
// week_page is listed in the menu when it is true, when it is left out and
// when its value is not accepted; false takes the page out of the menu, asks
// search engines to skip it (the unlisted mechanism of Data.Unlisted), and the
// page is still written, reachable by its address.
func TestRenderHandlesWeekPageByItsSwitch(t *testing.T) {
	for name, tc := range map[string]struct {
		line string
		want config.PageMode
	}{
		"absent": {"", config.PageOn}, "true": {"week_page: true\n", config.PageOn},
		"false": {"week_page: false\n", config.PageUnlisted}, "not accepted": {"week_page: unlisted\n", config.PageOn},
		"quoted": {"week_page: \"false\"\n", config.PageOn},
	} {
		t.Run(name, func(t *testing.T) {
			dir := renderInto(t, "--config", writeConfig(t, validConfig+tc.line))
			wantMode(t, dir, weekModePage, tc.want)
		})
	}
}

// TestRenderWithoutAConfigListsTheWeekPage: no config, no switch, listed.
func TestRenderWithoutAConfigListsTheWeekPage(t *testing.T) {
	wantMode(t, renderInto(t), weekModePage, config.PageOn)
}

// TestARefusedWeekPageValueIsExplainedOnTheSettingsPage (forsgren#183): the
// settings page names the value as written and the reason, the default kept.
func TestARefusedWeekPageValueIsExplainedOnTheSettingsPage(t *testing.T) {
	dir := renderInto(t, "--config", writeConfig(t, validConfig+"week_page: unlisted\n"))
	settings := readSite(t, dir, "settings.html")
	refused := `<span class="written">unlisted</span> is not accepted: use true or false.`
	for _, want := range []string{"week_page", refused, "true, false"} {
		if !strings.Contains(settings, want) {
			t.Errorf("want %q on the settings page", want)
		}
	}
}

// TestCheckConfigWarnsAboutARefusedWeekPage: one setting not accepted, the
// warning on stderr, exit 0.
func TestCheckConfigWarnsAboutARefusedWeekPage(t *testing.T) {
	code, stdout, stderr := runCommand("check-config", "--config", writeConfig(t, "week_page: yes\n"+validConfig))
	if code != 0 || !strings.HasSuffix(stdout, "settings not accepted: 1\n") ||
		!strings.Contains(stderr, `invalid week_page "yes": use true or false; using the default true`) {
		t.Errorf("want exit 0 and one refusal, got %d, %q, %q", code, stdout, stderr)
	}
}
