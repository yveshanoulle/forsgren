package needs

import (
	"strings"
	"testing"
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
	all, err := For("0.3.8")
	if err != nil {
		t.Fatal(err)
	}
	if got, want := Title("0.3.8"), "forsgren 0.3.8 needs more configuration"; got != want {
		t.Errorf("Title: want %q, got %q", want, got)
	}
	body := Body("0.3.8", all)
	if !strings.HasPrefix(body, Marker) {
		t.Errorf("Body: want it to start with %q, got %q", Marker, body)
	}
	if !strings.Contains(body, "forsgren 0.3.8") {
		t.Errorf("Body: want it to name %q, got %q", "forsgren 0.3.8", body)
	}
	if !strings.Contains(body, wantIssuesWriteSteps) {
		t.Errorf("Body: want it to contain %q, got %q", wantIssuesWriteSteps, body)
	}
}
