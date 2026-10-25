package needs

import (
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// The items of the pull request and push reads GitHub refused (forsgren#321,
// step 2, and forsgren#414): an observed refusal, not a claim about what
// works (decision #314), naming the token that was refused, never its value,
// and the fix that token needs.

// readKind is one of the two reads that can be refused: what its items say
// and how they are made.
type readKind struct {
	name    string
	refused func(history.Denied) []Need
	noun    string // the read, as an item names it
	tail    string // ends every item: where it comes from and when it goes
	jobFix  string // the fix of the job's token
	tokFix  string // the fix of any other token, up to the repository
}

var readKinds = []readKind{
	{"pulls", Refused, "pull request",
		" This item shows a refusal collect saw; it goes away when a run reads the pull requests of ",
		"Add `pull-requests: read` to the `permissions:` of the forsgren job in .github/workflows/forsgren.yml.",
		"the repository permission Pull requests: Read for "},
	{"pushes", RefusedPushes, "push",
		" This item shows a refusal collect saw; it goes away when a run reads the pushes of ",
		"Add `contents: read` to the `permissions:` of the forsgren job in .github/workflows/forsgren.yml.",
		"the repository permission Contents: Read for "},
}

// eachRead runs check as a subtest of every kind of read.
func eachRead(t *testing.T, check func(*testing.T, readKind)) {
	t.Helper()
	for _, k := range readKinds {
		t.Run(k.name, func(t *testing.T) { check(t, k) })
	}
}

// item is the text of the item for repository, refused with how, the words
// after "forsgren was refused the <noun> read of <repository>".
func (k readKind) item(repository, how string) string {
	return "forsgren was refused the " + k.noun + " read of " + repository + how + k.tail + repository + "."
}

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
	eachRead(t, func(t *testing.T, k readKind) {
		for _, c := range []struct{ token, how string }{
			{"GITHUB_TOKEN", " with GITHUB_TOKEN, the job's token. " + k.jobFix},
			{"FORSGREN_TOKEN", " with FORSGREN_TOKEN. Give FORSGREN_TOKEN " + k.tokFix + "acme/app."},
			{"", "; the file that notes it does not name the token. If the token is FORSGREN_TOKEN, give it " +
				k.tokFix + "acme/app; if it is the job's token, " + strings.ToLower(k.jobFix[:1]) + k.jobFix[1:]},
		} {
			t.Run(c.token, func(t *testing.T) {
				wantSteps(t, k.refused(history.Denied{"acme/app": refusedAt(c.token)}), k.item("acme/app", c.how))
			})
		}
	})
}

// TestRefusedHasNoItemForNoRefusal: no refusal, no item.
func TestRefusedHasNoItemForNoRefusal(t *testing.T) {
	eachRead(t, func(t *testing.T, k readKind) { wantSteps(t, k.refused(history.Denied{})) })
}

// TestRefusedHasOneItemPerRepositorySorted: acme/app comes before acme/lib.
func TestRefusedHasOneItemPerRepositorySorted(t *testing.T) {
	eachRead(t, func(t *testing.T, k readKind) {
		items := k.refused(history.Denied{"acme/lib": refusedAt("GITHUB_TOKEN"), "acme/app": refusedAt("GITHUB_TOKEN")})
		how := " with GITHUB_TOKEN, the job's token. " + k.jobFix
		wantSteps(t, items, k.item("acme/app", how), k.item("acme/lib", how))
	})
}
