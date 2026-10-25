package needs

import (
	"os"
	"path"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

// outsideRoot is a checkout directory inside a parent directory that also
// holds a workflow granting issues at write: the file a need must not reach.
func outsideRoot(t *testing.T) (root, outside string) {
	t.Helper()
	parent := t.TempDir()
	root = filepath.Join(parent, "checkout")
	outside = filepath.Join(parent, "outside.yml")
	writeFile(t, outside, withIssuesWrite)
	writeFile(t, filepath.Join(root, "README.md"), "acme\n")
	return root, outside
}

// TestAWorkflowOutsideTheCheckoutIsNotRead (forsgren#407): a permission need
// whose workflow leaves the checkout, by .. or by an absolute path, is not
// read and counts as not in place, though the file there grants it.
func TestAWorkflowOutsideTheCheckoutIsNotRead(t *testing.T) {
	root, outside := outsideRoot(t)
	for _, workflow := range []string{"../outside.yml", outside} {
		need := Need{Version: "0.3.8", Kind: "permission", Workflow: workflow,
			Permission: "issues", Access: "write"}
		got := Missing([]Need{need}, Installation{Root: root})
		if !reflect.DeepEqual(got, []Need{need}) {
			t.Errorf("workflow %s: want it missing, got %v", workflow, got)
		}
	}
}

// TestAMissingCheckoutRootMakesThePermissionNeedMissing (forsgren#407): a
// root that cannot be opened reads nothing, so the need is not in place.
func TestAMissingCheckoutRootMakesThePermissionNeedMissing(t *testing.T) {
	need := permissionNeed("write")
	got := Missing([]Need{need}, Installation{Root: filepath.Join(t.TempDir(), "absent")})
	if !reflect.DeepEqual(got, []Need{need}) {
		t.Errorf("want the need missing under a root that is not there, got %v", got)
	}
}

// TestASymlinkLeavingTheCheckoutIsNotFollowed (forsgren#407): a workflow in
// .github/workflows that is a symlink to a granting file outside the
// checkout is not followed and counts as not in place.
func TestASymlinkLeavingTheCheckoutIsNotFollowed(t *testing.T) {
	root, outside := outsideRoot(t)
	link := filepath.Join(root, callerWorkflow)
	if err := os.MkdirAll(filepath.Dir(link), 0o750); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, link); err != nil {
		t.Fatal(err)
	}
	need := permissionNeed("write")
	got := Missing([]Need{need}, Installation{Root: root})
	if !reflect.DeepEqual(got, []Need{need}) {
		t.Errorf("want the need missing behind a symlink out of the checkout, got %v", got)
	}
}

// TestEveryBuiltInWorkflowIsARelativePathUnderTheWorkflowsFolder
// (forsgren#407): each workflow: of needs.yml is clean, relative and under
// .github/workflows/, with no ..
func TestEveryBuiltInWorkflowIsARelativePathUnderTheWorkflowsFolder(t *testing.T) {
	all, err := For("999.999.999")
	if err != nil {
		t.Fatal(err)
	}
	for _, n := range all {
		if n.Workflow != "" && !underWorkflows(n.Workflow) {
			t.Errorf("need %s: workflow %q is not a clean relative path under .github/workflows/", n.Permission, n.Workflow)
		}
	}
}

// underWorkflows reports whether name is clean, relative, under
// .github/workflows/ and free of ..
func underWorkflows(name string) bool {
	return path.Clean(name) == name &&
		strings.HasPrefix(name, ".github/workflows/") &&
		!strings.Contains(name, "..")
}
