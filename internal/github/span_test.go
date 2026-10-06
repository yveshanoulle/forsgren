package github

import (
	"context"
	"net/url"
	"testing"
)

// TestDeploymentsKeepsOnlyWhatIsInTheSpan (forsgren#57): GitHub lists
// deployments with no date filter, so a span with an Until pages from the
// newest and keeps the deployments created from Since and before Until.
func TestDeploymentsKeepsOnlyWhatIsInTheSpan(t *testing.T) {
	f := newFake(t)
	f.on(deploymentsPath, reply{body: fixture(t, "deployments.json")})
	span := Span{Since: at(5, 0, 0, 0), Until: at(15, 0, 0, 0)}
	got, truncated, err := f.client(t, DefaultMaxPages).Deployments(context.Background(), "acme/app", "production", span)
	if err != nil || truncated || len(got) != 1 || got[0].ID != 1002 {
		t.Errorf("want only deployment 1002 and no error, got %v, truncated=%v, %v", got, truncated, err)
	}
}

// TestRunsAsksForTheRangeOfTheSpan (forsgren#57): the created filter is the
// range from the day before Since to the day after Until, and a run created
// from Until on is dropped here.
func TestRunsAsksForTheRangeOfTheSpan(t *testing.T) {
	f := newFake(t)
	f.on(runsPath, reply{body: fixture(t, "workflow-runs.json")})
	span := Span{Since: since, Until: at(15, 0, 0, 0)}
	got, _, err := f.client(t, DefaultMaxPages).Runs(context.Background(), "acme/app", "deploy.yml", "trunk", span)
	if err != nil || len(got) != 1 || got[0].ID != 5001 {
		t.Errorf("want only run 5001 and no error, got %v, %v", got, err)
	}
	wantQuery(t, f, url.Values{"created": {"2026-07-31..2026-09-16"}})
}
