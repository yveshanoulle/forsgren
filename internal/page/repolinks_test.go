package page

import (
	"os/exec"
	"testing"
)

// TestNoProjectsSitePassesTheRepositoryLinksGate runs the real gate,
// Scripts/check_repo_links.sh, on a site written with no projects configured:
// a new installation's first render. The how-to page used to link a docs file
// on github.com, a repository path the gate refuses, so that first render was
// the one case the gate would have failed (forsgren#172).
func TestNoProjectsSitePassesTheRepositoryLinksGate(t *testing.T) {
	dir := t.TempDir()
	data := calculated()
	data.NoProjects = true
	if _, err := WriteSite(dir, data); err != nil {
		t.Fatalf("WriteSite: %v", err)
	}
	// The site to scan is an absolute path, since
	// the gate changes into the repository root first.
	gate := exec.Command("../../Scripts/check_repo_links.sh")
	gate.Args = append(gate.Args, dir)
	if out, err := gate.CombinedOutput(); err != nil {
		t.Errorf("the repository-links gate refuses the no-projects site: %v\n%s", err, out)
	}
}
