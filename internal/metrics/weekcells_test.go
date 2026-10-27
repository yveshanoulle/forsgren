package metrics

import (
	"fmt"
	"testing"
)

// The Week table's cells (forsgren#531, step 2, decision #534 A): the Total
// is the row's counts with the thousands rule of forsgren#528; a weekday is
// the share of the row's commits (or deployments) on it, written as the TBD
// shares are (forsgren#540, decision #541), a dash when the row has none; a row Per
// repository writes an en dash for its commits (decision #539 A).

func TestWeekTotalsAreCountsWithTheThousandsRule(t *testing.T) {
	row := WeekRow{Commits: [weekdays]int{1000, 300, 41, 0, 0, 0, 0}, Deployments: [weekdays]int{4, 0, 0, 12, 0, 0, 0}}
	if got, want := row.CommitsTotalCell(), "1"+ThousandsSpace+"341"; got != want {
		t.Errorf("commits total: want %q, got %q", want, got)
	}
	if got, want := row.DeploymentsTotalCell(), "16"; got != want {
		t.Errorf("deployments total: want %q, got %q", want, got)
	}
}

func TestWeekSharesAreTbdSharePercentsOfTheRowsTotal(t *testing.T) {
	row := WeekRow{Commits: [weekdays]int{3, 0, 1, 0, 0, 0, 0}, Deployments: [weekdays]int{1, 2, 0, 0, 0, 0, 0}}
	for day, want := range []string{"75%", "0%", "25%", "0%", "0%", "0%", "0%"} {
		if got := row.CommitsShareCell(day); got != want {
			t.Errorf("commits day %d: want %q, got %q", day, want, got)
		}
	}
	for day, want := range []string{"33%", "66%", "0%"} {
		if got := row.DeploymentsShareCell(day); got != want {
			t.Errorf("deployments day %d: want %q, got %q", day, want, got)
		}
	}
}

func TestWeekSharesOfTheCommitsSumToAHundredPercentLessRounding(t *testing.T) {
	row := WeekRow{Commits: [weekdays]int{31, 40, 1234, 8, 17, 6, 2}}
	sum := 0.0
	for day := range row.Commits {
		var share float64
		if _, err := fmt.Sscanf(row.CommitsShareCell(day), "%f%%", &share); err != nil {
			t.Fatal(err)
		}
		sum += share
	}
	if sum < 93 || sum > 100 {
		t.Errorf("want the seven shares to sum to 100%% less rounding down, got %.2f", sum)
	}
}

func TestWeekRowWithoutCommitsOrDeploymentsReadsZeroAndDashes(t *testing.T) {
	row := WeekRow{Deployments: [weekdays]int{0, 0, 2, 0, 0, 0, 0}}
	if got, want := row.CommitsTotalCell(), "0"; got != want {
		t.Errorf("commits total: want %q, got %q", want, got)
	}
	if got, want := row.CommitsShareCell(2), "-"; got != want {
		t.Errorf("commits share: want %q, got %q", want, got)
	}
	empty := WeekRow{Commits: [weekdays]int{1, 0, 0, 0, 0, 0, 0}}
	if got, want := empty.DeploymentsTotalCell(), "0"; got != want {
		t.Errorf("deployments total: want %q, got %q", want, got)
	}
	if got, want := empty.DeploymentsShareCell(0), "-"; got != want {
		t.Errorf("deployments share: want %q, got %q", want, got)
	}
}

func TestWeekRowPerRepositoryWritesAnEnDashForItsCommitsAndKeepsItsDeployments(t *testing.T) {
	row := WeekRow{PerRepository: true, Deployments: [weekdays]int{0, 3, 1, 0, 0, 0, 0}}
	for _, got := range []string{row.CommitsTotalCell(), row.CommitsShareCell(0), row.CommitsShareCell(1)} {
		if want := "\u2013"; got != want {
			t.Errorf("want an en dash %q, got %q", want, got)
		}
	}
	if got, want := row.DeploymentsTotalCell(), "4"; got != want {
		t.Errorf("deployments total: want %q, got %q", want, got)
	}
	if got, want := row.DeploymentsShareCell(1), "75%"; got != want {
		t.Errorf("deployments share: want %q, got %q", want, got)
	}
}
