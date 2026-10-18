package page

import (
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// TestNumbersScoringPageFollowsTheDoraWindow (forsgren#55, decision 6): both
// halves of the frequency cell come from the same row, so they follow
// dora_days: three successful deployments 45 days ago count over 90 days
// (3, and the score of their band) but not over 30, where the window holds
// none (0, and the score of the last 180 days' band).
func TestNumbersScoringPageFollowsTheDoraWindow(t *testing.T) {
	at := time.Date(2026, 10, 3, 12, 0, 0, 0, time.UTC)
	deployed := func(id int64, ago time.Duration) history.Record {
		return history.Record{Project: "any", Repository: "acme/app", Kind: history.KindEnvironment,
			Name: "production", ID: id, Commit: "0123456789abcdef0123456789abcdef01234567",
			CreatedAt: at.Add(-ago), State: history.StateSuccess}
	}
	const day = 24 * time.Hour
	records := []history.Record{deployed(1, 250*day), deployed(2, 45*day), deployed(3, 46*day), deployed(4, 47*day)}
	shop := []config.Project{{Name: "Acme Shop", Repositories: []config.Repository{{Name: "acme/app"}}}}
	for days, want := range map[int]string{30: "0 · 2", 90: "3 · 4"} {
		data := Placeholder("1.11.0")
		data.Rows = Table(metrics.Rows(shop, metrics.Data{Records: records, WorkingHours: config.DefaultWorkingHours,
			DoraDays: days}, at))
		got := rendered(t, "numbers-scoring/index.html", data)
		if !row("Acme Shop", want).MatchString(got) {
			t.Errorf("dora_days %d: want the frequency cell %q, got:\n%s", days, want, got)
		}
	}
}
