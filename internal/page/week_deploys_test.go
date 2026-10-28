package page

import "testing"

// The weekday groups of the Week page head their deployments column Deploys
// (forsgren#552 step 2), which saves width; the Total group keeps
// Deployments, and every aria-label keeps the full word.

// TestWeekPageHeadsWeekdayDeploymentsDeploys: seven Deploys headers, one per
// weekday, each labelled with the full word; one Deployments header, under
// Total; in both week_commits modes.
func TestWeekPageHeadsWeekdayDeploymentsDeploys(t *testing.T) {
	for _, data := range []Data{weekPageData(), weekPageDataWithoutCommits()} {
		got := rendered(t, "week.html", data)
		wantAll(t, "week.html", got,
			`<th scope="col" aria-label="Total deployments" class="num">Deployments</th>`,
			`<th scope="col" aria-label="Monday deployments" class="num">Deploys</th>`,
			`<th scope="col" aria-label="Sunday deployments" class="num">Deploys</th>`)
		wantCount(t, got, `class="num">Deploys</th>`, 7)
		wantCount(t, got, `class="num">Deployments</th>`, 1)
		wantNone(t, "week.html", got, `aria-label="Monday deploys"`)
	}
}
