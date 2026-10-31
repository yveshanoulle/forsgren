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

// deploysHighestCell is a Deploys share cell marked highest: blue, and the
// same hidden word as the red marks (forsgren#597).
func deploysHighestCell(text string) string { return markedCell("highest-deploys", text) }

// TestWeekPageMarksTheHighestDeploysShareOfEachRowBlue (forsgren#597): in
// weekPageData the highest Deploys share is Wednesday's 31% of Acme Shop,
// Sunday's 25% of Website, Friday's 33% of API, Sunday's 27% of Acme Docs and
// Sunday's 25% of the Total (15 of 58), one cell a row, in both week_commits
// modes; the Commits shares, Acme Shop's Wednesday 92% the highest, are not
// marked.
func TestWeekPageMarksTheHighestDeploysShareOfEachRowBlue(t *testing.T) {
	for _, data := range []Data{weekPageData(), weekPageDataWithoutCommits()} {
		got := rendered(t, "week.html", data)
		wantAll(t, "week.html", got, deploysHighestCell("31%"), deploysHighestCell("33%"),
			deploysHighestCell("27%"))
		wantCount(t, got, deploysHighestCell("25%"), 2)
		wantCount(t, got, `class="num highest-deploys"`, 5)
	}
}

// TestWeekPageMarksNoDeploysShareOfARowWithoutDeployments: with no
// deployments on any row, no Deploys share is blue.
func TestWeekPageMarksNoDeploysShareOfARowWithoutDeployments(t *testing.T) {
	data := weekPageData()
	for i := range data.Week.Rows {
		data.Week.Rows[i].Deployments = [7]int{}
	}
	wantNone(t, "week.html", rendered(t, "week.html", data), "highest-deploys")
}
