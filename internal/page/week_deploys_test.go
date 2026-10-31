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

// TestWeekPageMarksTheHighestDeploysShareOfEachRowBlue (forsgren#597), the
// deployments successful plus failed (forsgren#601): in weekPageData the
// highest Deploys share is Wednesday's 33% of Acme Shop (12 of 36), Sunday's
// 25% of Website, Friday's 35% of API (14 of 39), Sunday's 27% of Acme Docs
// and Sunday's 27% of the Total (18 of 65), one cell a row; the Commits
// shares, Acme Shop's Wednesday 92% the highest, are not marked.
func TestWeekPageMarksTheHighestDeploysShareOfEachRowBlue(t *testing.T) {
	got := rendered(t, "week.html", weekPageData())
	wantAll(t, "week.html", got, deploysHighestCell("33%"), deploysHighestCell("25%"), deploysHighestCell("35%"))
	wantCount(t, got, deploysHighestCell("27%"), 2)
	wantCount(t, got, `class="num highest-deploys"`, 5)
}

// TestWeekPageMarksTheHighestDeploysShareWithTheFailuresOfEveryRow: in
// weekPageDataWithoutCommits Website's failures tie Friday to Sunday at 7 of
// 35, 20% each, and Acme Docs' put Sunday at 12 of 36, 33%, as Acme Shop's
// Wednesday; the Total's Sunday is 22 of 72, 30% (forsgren#601).
func TestWeekPageMarksTheHighestDeploysShareWithTheFailuresOfEveryRow(t *testing.T) {
	got := rendered(t, "week.html", weekPageDataWithoutCommits())
	wantAll(t, "week.html", got, deploysHighestCell("35%"), deploysHighestCell("30%"))
	wantCount(t, got, deploysHighestCell("20%"), 3)
	wantCount(t, got, deploysHighestCell("33%"), 2)
	wantCount(t, got, `class="num highest-deploys"`, 7)
}

// TestWeekPageMarksNoDeploysShareOfARowWithoutDeployments: with no
// deployments, successful or failed, on any row, no Deploys share is blue.
func TestWeekPageMarksNoDeploysShareOfARowWithoutDeployments(t *testing.T) {
	data := weekPageData()
	for i := range data.Week.Rows {
		data.Week.Rows[i].Deployments = [7]int{}
		data.Week.Rows[i].Failed = [7]int{}
	}
	wantNone(t, "week.html", rendered(t, "week.html", data), "highest-deploys")
}
