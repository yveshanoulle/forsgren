package page

import "testing"

// The Failed and Fail rate columns of the Week page (forsgren#545, decision
// #546), and the highest weekday value of each in red. weekPageData: Acme Shop
// failed {1,0,3,0,0,0,3} of successful plus failed {5,5,12,1,0,3,10}; Website none; API
// one on Friday of 14; Acme Docs none.

// markedCell is a cell marked with class: the class after num, and the hidden
// word highest.
func markedCell(class, text string) string {
	return `<td class="num ` + class + `">` + text + hiddenHighest + `</td>`
}

// hiddenHighest is the visually hidden word of a marked cell.
const hiddenHighest = `<span class="visually-hidden"> highest</span>`

// highestCell is a Failed or Fail rate cell marked highest, red.
func highestCell(text string) string { return markedCell("highest", text) }

// TestWeekPageFailedCellsAreACountInTotalAndSharesPerWeekday: Total is the
// count of failures and the rate over the window; a weekday is the share of
// the failures and the failures over that weekday's successful plus failed deployments, a
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
// hidden word says it for a screen reader. The Total row (forsgren#552) is marked as a project row:
// Wednesday and Sunday in Failed, Wednesday in Fail rate. The hidden word is
// also in the five blue Deploys cells (forsgren#597).
func TestWeekPageMarksTheHighestFailedAndFailRateOfEachRow(t *testing.T) {
	got := rendered(t, "week.html", weekPageData())
	wantAll(t, "week.html", got, highestCell("42%"), highestCell("30%"), highestCell("66%"), highestCell("20%"))
	wantCount(t, got, highestCell("42%"), 2+2)
	wantCount(t, got, `class="num highest"`, 5+3)
	wantCount(t, got, hiddenHighest, 5+3+5)
}

// TestWeekPageMarksNoTotalCellAndNoRowWithoutFailures: with the failures of
// the first rows gone, no cell is red; the hidden word stays only in the
// five blue Deploys cells.
func TestWeekPageMarksNoTotalCellAndNoRowWithoutFailures(t *testing.T) {
	data := weekPageData()
	for i := range data.Week.Rows {
		data.Week.Rows[i].Failed = [7]int{}
	}
	got := rendered(t, "week.html", data)
	wantNone(t, "week.html", got, `class="num highest"`)
	wantCount(t, got, hiddenHighest, 5)
}
