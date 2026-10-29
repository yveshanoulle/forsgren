package page

import (
	"regexp"
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/config"
)

// legendItem is one item of the legend page's band lists.
var legendItem = regexp.MustCompile(`<li>[^<]*</li>`)

// TestTablePageLinksToTheLegend (forsgren#39, step 1): the table page
// carries a link to legend.html and none of the band explanations: no item
// of the legend page's band lists (forsgren#39, step 4).
func TestTablePageLinksToTheLegend(t *testing.T) {
	data := acmeTable()
	got := rendered(t, "index.html", data)
	if !strings.Contains(got, `<a href="legend.html">Legend</a>`) {
		t.Errorf("want a link to legend.html on the table page, got:\n%s", got)
	}
	if strings.Contains(got, "<h2>Legend</h2>") {
		t.Errorf("want the legend off the table page, got:\n%s", got)
	}
	items := legendItem.FindAllString(rendered(t, "legend.html", data), -1)
	if len(items) == 0 {
		t.Fatal("want band lists on the legend page, found none")
	}
	for _, item := range items {
		if strings.Contains(got, item) {
			t.Errorf("want the legend's %s off the table page", item)
		}
	}
}

// TestLegendPageSaysWhereEachMetricComesFrom (forsgren#41, step 1): the
// paragraph that left the table page is on the legend page, one source per
// metric.
func TestLegendPageSaysWhereEachMetricComesFrom(t *testing.T) {
	wantAll(t, "legend.html", rendered(t, "legend.html", Placeholder(testVersion)),
		"Every number counts back from the time in the footer: deployment frequency from the successful deployments",
		"lead time for changes from the commits they shipped",
		"failed deployment recovery time from the failed deployments and the successful ones after them "+
			"and from the issues labelled failure",
		"change fail rate from the failed deployments and the issues labelled failure",
		"deployment rework rate from the successful deployments that came after a failed deployment",
	)
}

// TestLegendPageCreditsTheDoraQuickCheck (forsgren#47): the legend page says
// where the scores come from, word for word the credit the Quick Check's
// licence asks for, with the Quick Check and the licence each linked.
func TestLegendPageCreditsTheDoraQuickCheck(t *testing.T) {
	const want = `Scores follow the <a href="https://dora.dev/quickcheck/">DORA Quick Check</a> (dora.dev), ` +
		`© Google LLC, <a href="https://creativecommons.org/licenses/by/4.0/">CC BY 4.0</a>.`
	wantAll(t, "legend.html", rendered(t, "legend.html", Placeholder(testVersion)), want)
}

// TestLegendStatesTheWorkingDay (forsgren#71): the legend says how a working
// day is configured, and its on-demand and hourly-to-daily numbers follow:
// a set 12 gives more than 12 x 30 = 360, so 361 and more; unset says it is
// the default 8.
func TestLegendStatesTheWorkingDay(t *testing.T) {
	cases := []struct {
		name  string
		hours int
		set   bool
		want  []string
	}{
		{"set", 12, true, []string{"A working day is configured as 12 hours.", "361 and more", "30 to 360"}},
		{"unset", 8, false, []string{
			"A working day is configured as 8 hours (the default; working_hours is not set in forsgren.config.yml).",
			"241 and more", "30 to 240",
		}},
	}
	for _, c := range cases {
		data := Placeholder(testVersion)
		data.WorkingHours, data.WorkingHoursSet = c.hours, c.set
		wantAll(t, c.name, rendered(t, "legend.html", data), c.want...)
	}
}

// TestLegendHasNoSettings (forsgren#84, step 2): the settings moved to their
// own page; the legend has no Settings section and no setting.
func TestLegendHasNoSettings(t *testing.T) {
	data := withTwoSettings()
	wantNone(t, "legend.html", rendered(t, "legend.html", data),
		"<h2>Settings</h2>",
		"<li>view: numbers</li>",
		"<li>history_days: 365",
	)
}

// defaultNote is the legend's explanation of the settings page's Default
// column and of "(not set)" after a Current value (forsgren#141, #169).
const defaultNote = "The Default column of the settings page is the value used when forsgren.config.yml does not " +
	"set the key. A current value followed by (not set) means the file does not set the key, so the default applies; " +
	"a current value without it is set in the file, even to the default's value."

// TestLegendExplainsTheDefaultColumnAndNotSet (forsgren#141, #169): the legend
// ends with a section on the settings page that says what the Default column
// holds and what (not set) after a Current value means, and no longer speaks
// of True and False.
func TestLegendExplainsTheDefaultColumnAndNotSet(t *testing.T) {
	html := rendered(t, "legend.html", calculated())
	wantAll(t, "legend.html", html, "<h2>Settings page</h2>\n    <p>"+defaultNote+"</p>\n")
	wantNone(t, "legend.html", html, "True when forsgren.config.yml")
}

// autoUpdateLevelNote is the legend's explanation of auto_update_level and of
// a patch, a minor and a major release (forsgren#156).
const autoUpdateLevelNote = "auto_update_level is the largest step of a forsgren update that merges itself; a " +
	"larger one is left for you. By what a release asks of an installation, a patch release is fixes only, with " +
	"nothing new for the installation to do or see; a minor release is new behaviour, or anything that asks the " +
	"installation for something (a permission, a secret, a file, a config key); a major release is one where an " +
	"installation that does nothing would stop working."

// TestLegendExplainsAutoUpdateLevels (forsgren#156): the legend's settings
// section says what a patch, a minor and a major release are, and what each
// auto_update_level merges by itself; the levels come from the config's
// constants, so a renamed level fails here.
func TestLegendExplainsAutoUpdateLevels(t *testing.T) {
	wantAll(t, "legend.html", rendered(t, "legend.html", calculated()),
		"<p>"+autoUpdateLevelNote+"</p>",
		"<li>"+config.LevelPatch+": merges "+config.LevelPatch+" updates only</li>",
		"<li>"+config.LevelMinor+": merges "+config.LevelMinor+" and "+config.LevelPatch+" updates</li>",
		"<li>"+config.LevelMajor+": merges "+config.LevelMajor+", "+config.LevelMinor+" and "+config.LevelPatch+
			" updates. It does not mean a major release is safe: nothing checks a release against this "+
			"installation's own data.</li>")
}
