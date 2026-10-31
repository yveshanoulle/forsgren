package dictionary

import (
	"strings"
	"testing"
)

// TestTheMainlineIntervalEntryNamesThePushedCommits (forsgren#588): the
// interval is measured over the commits pushed to the main branch at their
// author dates, not over the commits that deployments shipped, so the entry
// says so and its From line names the push files, not data/commits.csv.
func TestTheMainlineIntervalEntryNamesThePushedCommits(t *testing.T) {
	e := entryNamed(t, "Mainline Interval")
	for _, phrase := range unsaid(e.Definition, []string{"pushed to the main branch", "author date",
		"deployed or not"}) {
		t.Errorf("want the definition to say %q, got %q", phrase, e.Definition)
	}
	for _, file := range unsaid(e.From, []string{"data/pushes.csv", "data/push_commits.csv"}) {
		t.Errorf("want the From line to name %s, got %q", file, e.From)
	}
	if strings.Contains(e.Definition, "deployments shipped") || strings.Contains(e.From, "data/commits.csv") {
		t.Errorf("want no deployed commits in the entry, got %q from %q", e.Definition, e.From)
	}
}
