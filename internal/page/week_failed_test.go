package page

import "testing"

// The Failed and Fail rate columns of the Week page (forsgren#545, decision
// #546), and the highest weekday value of each in red. weekPageData: Acme Shop
// failed {1,0,3,0,0,0,3} of finished {5,5,12,1,0,3,10}; Website none; API
// one on Friday of 13 finished; Acme Docs none.

// highestCell is a cell marked highest: the class and the hidden word.
func highestCell(text string) string {
	return `<td class="num highest">` + text + `<span class="visually-hidden"> highest</span></td>`
}

// TestWeekPageFailedCellsAreACountInTotalAndSharesPerWeekday: Total is the
// count of failures and the rate over the window; a weekday is the share of
// the failures and the failures over that weekday's finished deployments, a
// dash where there is nothing to divide.
func TestWeekPageFailedCellsAreACountInTotalAndSharesPerWeekday(t *testing.T) {
	got := rendered(t, "week.html", weekPageData())
	wantAll(t, "week.html", got,
		`<td class="num">7</td>`, `<td class="num">19%</td>`,
		`<td class="num">14%</td>`, `<td class="num">20%</td>`, `<td class="num">25%</td>`,
		`<td class="num">0%</td>`, `<td class="num">-</td>`)
}

// TestWeekPageMarksTheHighestFailedAndFailRateOfEachRow: every tied day of
// Failed (Wednesday and Sunday of Acme Shop), the highest Fail rate (Sunday),
// the Friday of API in Failed and its Wednesday in Fail rate, and nothing in a row without failures; the
// hidden word says it for a screen reader.
func TestWeekPageMarksTheHighestFailedAndFailRateOfEachRow(t *testing.T) {
	got := rendered(t, "week.html", weekPageData())
	wantAll(t, "week.html", got, highestCell("42%"), highestCell("30%"), highestCell("66%"), highestCell("20%"))
	wantCount(t, got, highestCell("42%"), 2)
	wantCount(t, got, `class="num highest"`, 5)
	wantCount(t, got, `<span class="visually-hidden"> highest</span>`, 5)
}

// TestWeekPageMarksNoTotalCellAndNoRowWithoutFailures: with the failures of
// the first rows gone, no cell is marked.
func TestWeekPageMarksNoTotalCellAndNoRowWithoutFailures(t *testing.T) {
	data := weekPageData()
	for i := range data.Week.Rows {
		data.Week.Rows[i].Failed = [7]int{}
	}
	got := rendered(t, "week.html", data)
	wantNone(t, "week.html", got, "highest")
}
