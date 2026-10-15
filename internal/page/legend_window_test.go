package page

import "testing"

// TestLegendStatesTheDoraWindow (forsgren#178): the legend says the window and
// every window-dependent line follows it, with the band edges of the window
// at 8 hours: 90 days start weekly to monthly at 3, daily to weekly at 15,
// hourly to daily at 90 and on demand at 721; 180 days at 6, 30, 180 and
// 1441. The duration edges and the issues pages keep their own days.
func TestLegendStatesTheDoraWindow(t *testing.T) {
	cases := []struct {
		name string
		days int
		set  bool
		want []string
	}{
		{"90 set", 90, true, []string{
			"The window is 90 days (dora_days in forsgren.config.yml).",
			"the successful deployments of the last 90 days, or of the last 180 days when the 90 days hold none",
			"721 and more in 90 days", "90 to 720 in 90 days", "15 to 89 in 90 days", "3 to 14 in 90 days",
			"fewer than 3 in 90 days, 1 and more in 180 days", "none in 180 days",
			"over the same 90 or 180 days; it is 0 when there are none. The numbers view shows the last 90 days.",
			"the commits deployed in the last 90 days. A month is 30 days",
			"the recoveries of the last 90 days", "the final deployments of the last 90 days",
			"the successful deployments of the last 90 days, in whole percent",
			"but forsgren measures the last 90 days, like its other four metrics",
			"One week to one month: 7 days to below 30 days",
		}},
		{"180 set", 180, true, []string{
			"The window is 180 days (dora_days in forsgren.config.yml).",
			"1441 and more in 180 days", "180 to 1440 in 180 days", "30 to 179 in 180 days", "6 to 29 in 180 days",
			"fewer than 6 in 180 days, 1 and more in 180 days",
			"over the same 180 days; it is 0 when there are none. The numbers view shows the last 180 days.",
		}},
		{"unset", 0, false, []string{
			"The window is 30 days (the default; dora_days is not set in forsgren.config.yml).",
			"241 and more in 30 days", "30 to 240 in 30 days", "5 to 29 in 30 days", "1 to 4 in 30 days",
			"none in 30 days, 1 and more in 180 days", "over the same 30 or 180 days;",
		}},
	}
	for _, c := range cases {
		data := Placeholder("1.6.2")
		data.DoraDays, data.DoraDaysSet = c.days, c.set
		wantAll(t, c.name, rendered(t, "legend.html", data), c.want...)
	}
}
