package main

import (
	"strings"
	"testing"
)

// labelledConfig is validConfig with labels (forsgren#38): acme/api names
// its one task API, acme/ios-app is one row, iOS; Acme Tools has none.
const labelledConfig = `version: 1
projects:
  - name: Acme Shop
    repositories:
      - name: acme/api
        services:
          ` + fixtureTask + `: API
      - name: acme/ios-app
        deployment: workflow=testflight.yml
        label: iOS
  - name: Acme Tools
    repositories:
      - name: acme/cli
        deployment: release
`

// TestRenderShowsLabelRows (forsgren#38): the labels of the config add rows
// under their project's total, sorted, each counted from its own
// deployments: acme/api's task has 3 successes in the last 30 days,
// acme/ios-app 9. The page shows the labels, never a repository's or a
// task's own name.
func TestRenderShowsLabelRows(t *testing.T) {
	pinNow(t)
	_, _, index := renderWith(t, "--config", writeConfig(t, labelledConfig), "--data", writeHistory(t, acmeHistory()))
	for _, want := range []string{
		`<th scope="row">Acme Shop (total)</th>`,
		`<tr class="label">
            <th scope="row"><span class="visually-hidden">Acme Shop: </span>API</th>
            <td>Between once per week and once per month · 3</td>`,
		`<tr class="label">
            <th scope="row"><span class="visually-hidden">Acme Shop: </span>iOS</th>
            <td>Between once per day and once per week · 9</td>`,
		`<th scope="row">Acme Tools</th>`,
	} {
		if !strings.Contains(index, want) {
			t.Errorf("want %q on the page, got:\n%s", want, index)
		}
	}
	if strings.Index(index, ">API<") > strings.Index(index, ">iOS<") {
		t.Errorf("want API before iOS, got:\n%s", index)
	}
	for _, private := range []string{"acme/", "acme-live", "testflight", fixtureCommit[:7], fixtureTask} {
		if strings.Contains(index, private) {
			t.Errorf("the page shows %q:\n%s", private, index)
		}
	}
}
