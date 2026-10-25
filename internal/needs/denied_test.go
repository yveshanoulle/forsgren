package needs

import (
	"slices"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// The items of the pull request reads GitHub refused (forsgren#321, step 2):
// an observed refusal, not a claim about what works (decision #314), naming
// the token that was refused, never its value, and the fix that token needs.

const (
	// wantTail ends every item: where it comes from and when it goes.
	wantTail     = " This item shows a refusal collect saw; it goes away when a run reads the pull requests of "
	wantJobFix   = "Add `pull-requests: read` to the `permissions:` of the forsgren job in .github/workflows/forsgren.yml."
	wantTokenFix = "the repository permission Pull requests: Read for "
)

func refusedAt(token string) history.Denial {
	return history.Denial{At: time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC), Token: token}
}

// stepsOf are the steps of items, in order.
func stepsOf(items []Need) []string {
	steps := make([]string, 0, len(items))
	for _, item := range items {
		steps = append(steps, item.Steps)
	}
	return steps
}

// wantSteps fails t unless the steps of items are want.
func wantSteps(t *testing.T, items []Need, want ...string) {
	t.Helper()
	if got := stepsOf(items); !slices.Equal(got, want) {
		t.Errorf("want the items %q, got %q", want, got)
	}
}

// TestRefusedNamesTheTokenAndItsFix: the job's token is fixed in the job's
// permissions, any other token, a fine-grained one, with its own repository
// permission; a v1 line, with no token name, gives both fixes and names none.
func TestRefusedNamesTheTokenAndItsFix(t *testing.T) {
	for _, c := range []struct{ token, want string }{
		{"GITHUB_TOKEN", "forsgren was refused the pull request read of acme/app with GITHUB_TOKEN, the job's token. " +
			wantJobFix + wantTail + "acme/app."},
		{"FORSGREN_TOKEN", "forsgren was refused the pull request read of acme/app with FORSGREN_TOKEN. " +
			"Give FORSGREN_TOKEN " + wantTokenFix + "acme/app." + wantTail + "acme/app."},
		{"", "forsgren was refused the pull request read of acme/app; the file that notes it does not name the token. " +
			"If the token is FORSGREN_TOKEN, give it " + wantTokenFix + "acme/app; if it is the job's token, " +
			"add `pull-requests: read` to the `permissions:` of the forsgren job in .github/workflows/forsgren.yml." +
			wantTail + "acme/app."},
	} {
		t.Run(c.token, func(t *testing.T) {
			wantSteps(t, Refused(history.PullsDenied{"acme/app": refusedAt(c.token)}), c.want)
		})
	}
}

// TestRefusedHasNoItemForNoRefusal: no refusal, no item.
func TestRefusedHasNoItemForNoRefusal(t *testing.T) {
	wantSteps(t, Refused(history.PullsDenied{}))
}

// TestRefusedHasOneItemPerRepositorySorted: acme/app comes before acme/lib.
func TestRefusedHasOneItemPerRepositorySorted(t *testing.T) {
	items := Refused(history.PullsDenied{"acme/lib": refusedAt("GITHUB_TOKEN"), "acme/app": refusedAt("GITHUB_TOKEN")})
	wantSteps(t, items,
		"forsgren was refused the pull request read of acme/app with GITHUB_TOKEN, the job's token. "+
			wantJobFix+wantTail+"acme/app.",
		"forsgren was refused the pull request read of acme/lib with GITHUB_TOKEN, the job's token. "+
			wantJobFix+wantTail+"acme/lib.")
}
