package page

import (
	"strconv"
	"strings"
	"testing"
)

// A service without paths (forsgren#496, step 4): its Time to deploy per
// commit and Commits per deployment are the repository's, so the row says Per
// repository there, as it does for Commits and Pushes; its Deployments stays
// its own. A service with paths shows its own figures.

// perRepositoryDeployRow is the row of the service API of subRowsData with its
// Time to deploy and Commits per deployment per repository too: one cell
// across each, three columns with all the figures.
func perRepositoryDeployRow(all bool) string {
	span := func(median, every int) string {
		if all {
			median = every
		}
		return "@" + strconv.Itoa(median) + perRepository
	}
	cells := []string{span(5, 15), span(1, 3), span(2, 2), "5", span(1, 3), span(1, 3), span(4, 4), "2"}
	return "<th scope=\"row\"><span class=\"visually-hidden\">Acme Shop: </span>API</th>\n            " +
		tds(strings.Join(cells, " | ")) + "\n"
}

// TestAServiceWithoutPathsSaysPerRepositoryForItsDeployFigures: the flag of the
// row turns the Time to deploy and Commits per deployment cells into one
// Per repository cell each, in both figure modes; the Volume cell stays its own.
func TestAServiceWithoutPathsSaysPerRepositoryForItsDeployFigures(t *testing.T) {
	for _, all := range []bool{false, true} {
		data := inFigures(subRowsData(), all)
		data.TbdMetrics[1].DeployPerRepository = true
		wantAll(t, "per repository", rendered(t, "tbd.html", data), perRepositoryDeployRow(all))
	}
}

// TestAServiceWithPathsShowsItsOwnDeployFigures: without the flag the cells are
// the service's own figures, as before.
func TestAServiceWithPathsShowsItsOwnDeployFigures(t *testing.T) {
	for _, all := range []bool{false, true} {
		wantAll(t, "with paths", rendered(t, "tbd.html", inFigures(subRowsData(), all)), apiRow(all))
	}
}

// TestTheTotalRowKeepsItsDeployFiguresWhenAServiceIsPerRepository: the total
// row has no Per repository cell whatever the flag of a service.
func TestTheTotalRowKeepsItsDeployFiguresWhenAServiceIsPerRepository(t *testing.T) {
	data := subRowsData()
	data.TbdMetrics[1].DeployPerRepository = true
	got := rendered(t, "tbd.html", data)
	total := got[strings.Index(got, ">Acme Shop</th>"):strings.Index(got, "Acme Shop: </span>API")]
	if strings.Contains(total, perRepository) {
		t.Errorf("want the total row without Per repository, got:\n%s", total)
	}
}
