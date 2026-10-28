package main

import (
	"strings"
	"testing"
)

// TestTheFixtureWeekPageShowsFailedDeploymentsOfTheCliRow (forsgren#545,
// decision #546): acme/cli has failed deployments on Tuesday 8 and 15
// September and Thursday 17 September, a successful one on Tuesday 22 and an
// other one on Wednesday 23. Failed is 3 of 6 finished (50%); Tuesday holds 2
// of the 3 failures (66%) and 2 of its 3 finished deployments fail (66%),
// Thursday holds 1 (33%) and fails 1 of 1 (100%); the highest Failed
// (Tuesday) and the highest Fail rate (Thursday) are marked, with their
// hidden word, and nothing else.
func TestTheFixtureWeekPageShowsFailedDeploymentsOfTheCliRow(t *testing.T) {
	row := rowOf(fixtureWeekPage(t), "Acme Tools", "CLI")
	for _, want := range []string{
		`<td class="num">3</td>`, `<td class="num">50%</td>`, `<td class="num">66%</td>`,
		`<td class="num">33%</td>`, `<td class="num">0%</td>`,
		`<td class="num highest">66%<span class="visually-hidden"> highest</span></td>`,
		`<td class="num highest">100%<span class="visually-hidden"> highest</span></td>`,
	} {
		if !strings.Contains(row, want) {
			t.Errorf("want %q in the CLI row, got %q", want, row)
		}
	}
	if got := strings.Count(row, `class="num highest"`); got != 2 {
		t.Errorf("want 2 highest cells (Failed on Tuesday, Fail rate on Thursday), got %d", got)
	}
}
