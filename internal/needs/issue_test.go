package needs

import (
	"strings"
	"testing"
	"time"
)

// wantIssuesWriteSteps is the least-privilege wording of the issues: write
// need's steps (forsgren#73).
const wantIssuesWriteSteps = "Add `issues: write` to the `permissions:` of the forsgren job in " +
	".github/workflows/forsgren.yml, so forsgren can open its setup issue. " +
	"forsgren requires permissions to be declared explicitly on that job: " +
	"`write-all` and `read-all` are intentionally unsupported, because " +
	"forsgren follows least-privilege security practice."

// TestSetupIssueTextForTheDeclaredNeeds (forsgren#73): the title names the
// version, and the body starts with the hidden marker, names the version and
// carries each missing need's steps.
func TestSetupIssueTextForTheDeclaredNeeds(t *testing.T) {
	all, err := For("0.4.0")
	if err != nil {
		t.Fatal(err)
	}
	if got, want := Title("0.4.0"), "forsgren 0.4.0 needs more configuration"; got != want {
		t.Errorf("Title: want %q, got %q", want, got)
	}
	body := Body("0.4.0", all)
	if !strings.HasPrefix(body, Marker) {
		t.Errorf("Body: want it to start with %q, got %q", Marker, body)
	}
	if !strings.Contains(body, "forsgren 0.4.0") {
		t.Errorf("Body: want it to name %q, got %q", "forsgren 0.4.0", body)
	}
	if !strings.Contains(body, wantIssuesWriteSteps) {
		t.Errorf("Body: want it to contain %q, got %q", wantIssuesWriteSteps, body)
	}
}

// TestTheTokenExpiryMarkRoundTripsThroughTheBody (forsgren#177): a need
// with Hidden text carries it after its steps in the body, and the date of
// the token expiry mark is read back exactly; a body without a mark, or with
// a mark that names no date, has none.
func TestTheTokenExpiryMarkRoundTripsThroughTheBody(t *testing.T) {
	expiry := time.Date(2026, 10, 10, 8, 35, 47, 0, time.UTC)
	item := Need{Steps: "renew it", Hidden: TokenExpiryMark(expiry)}
	body := Body("1.5.0", []Need{item})
	if want := "- [ ] renew it <!-- forsgren:token_expiry 2026-10-10T08:35:47Z -->"; !strings.Contains(body, want) {
		t.Errorf("Body: want %q, got %q", want, body)
	}
	if got, ok := TokenExpiryIn(body); !ok || !got.Equal(expiry) {
		t.Errorf("TokenExpiryIn: want %v, got %v (%v)", expiry, got, ok)
	}
	for _, none := range []string{Body("1.5.0", nil), "<!-- forsgren:token_expiry soon -->"} {
		if got, ok := TokenExpiryIn(none); ok {
			t.Errorf("TokenExpiryIn(%q): want none, got %v", none, got)
		}
	}
}
