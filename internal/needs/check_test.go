package needs

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

// TestMissingReportsAFileNeedThatIsNotInTheCheckout (forsgren#73): a need of
// kind file is in place when the file is in the installation's checkout, and
// missing when it is not.
func TestMissingReportsAFileNeedThatIsNotInTheCheckout(t *testing.T) {
	const path = ".github/workflows/forsgren-update.yml"
	need := Need{Version: "0.3.8", Kind: "file", File: path}
	cases := []struct {
		name    string
		present bool
		want    []Need
	}{
		{"absent", false, []Need{need}},
		{"present", true, nil},
	}
	for _, c := range cases {
		root := t.TempDir()
		if c.present {
			writeFile(t, root, path, "name: update\n")
		}
		got := Missing([]Need{need}, Installation{Root: root})
		if !reflect.DeepEqual(got, c.want) {
			t.Errorf("%s: want missing %v, got %v", c.name, c.want, got)
		}
	}
}

// TestMissingReportsAConfigKeyNeedThatTheConfigLacks (forsgren#73): a need of
// kind config_key is in place when its key is among the installation's config
// keys, and missing when it is not.
func TestMissingReportsAConfigKeyNeedThatTheConfigLacks(t *testing.T) {
	need := Need{Version: "0.3.8", Kind: "config_key", Key: "auto_update"}
	cases := []struct {
		name string
		keys []string
		want []Need
	}{
		{"absent", []string{"version", "projects"}, []Need{need}},
		{"present", []string{"version", "auto_update", "projects"}, nil},
	}
	for _, c := range cases {
		got := Missing([]Need{need}, Installation{ConfigKeys: c.keys})
		if !reflect.DeepEqual(got, c.want) {
			t.Errorf("%s: want missing %v, got %v", c.name, c.want, got)
		}
	}
}

const callerWorkflow = ".github/workflows/forsgren.yml"

// templateWorkflow is the caller workflow of forsgren-template: the grants of
// its job, none of them for issues.
const templateWorkflow = `permissions: {}
jobs:
  metrics:
    permissions:
      contents: write
      pages: write
      id-token: write
      pull-requests: read
    uses: yveshanoulle/forsgren/.github/workflows/metrics.yml@0123456789abcdef0123456789abcdef01234567 # v0.3.6
`

// withIssues is templateWorkflow with one more grant for the job, issues at
// the access given.
func withIssues(access string) string {
	return strings.Replace(templateWorkflow, "      pages: write\n",
		"      pages: write\n      issues: "+access+"\n", 1)
}

// permissionNeed is a need of kind permission for issues at the access given,
// in the caller workflow.
func permissionNeed(access string) Need {
	return Need{Version: "0.3.8", Kind: "permission", Workflow: callerWorkflow,
		Permission: "issues", Access: access}
}

// TestMissingReportsAPermissionNeedThatTheWorkflowDoesNotGrant (forsgren#73):
// a need of kind permission is in place when a job of the installation's
// caller workflow grants the permission at the access, or write for a need of
// read, and missing when the grant is absent or lower, or the file cannot be
// read or parsed.
func TestMissingReportsAPermissionNeedThatTheWorkflowDoesNotGrant(t *testing.T) {
	cases := []struct {
		name    string
		need    Need
		content *string
		inPlace bool
	}{
		{"no workflow file", permissionNeed("write"), nil, false},
		{"template shape, no issues", permissionNeed("write"), ptr(templateWorkflow), false},
		{"issues write", permissionNeed("write"), ptr(withIssues("write")), true},
		{"issues read only", permissionNeed("write"), ptr(withIssues("read")), false},
		{"not YAML", permissionNeed("write"), ptr("jobs: [unclosed\n\t: : -\n"), false},
		{"write satisfies read", permissionNeed("read"), ptr(withIssues("write")), true},
	}
	for _, c := range cases {
		assertPermissionNeed(t, c.name, c.need, c.content, c.inPlace)
	}
}

// assertPermissionNeed checks the need against a checkout holding the caller
// workflow with the content, or no workflow when content is nil.
func assertPermissionNeed(t *testing.T, name string, need Need, content *string, inPlace bool) {
	t.Helper()
	root := t.TempDir()
	if content != nil {
		writeFile(t, root, callerWorkflow, *content)
	}
	var want []Need
	if !inPlace {
		want = []Need{need}
	}
	got := Missing([]Need{need}, Installation{Root: root})
	if !reflect.DeepEqual(got, want) {
		t.Errorf("%s: want missing %v, got %v", name, want, got)
	}
}

func ptr(s string) *string { return &s }

// writeFile writes the file at the relative path rel under root with the
// content, with its directories.
func writeFile(t *testing.T, root, rel, content string) {
	t.Helper()
	full := filepath.Join(root, rel)
	if err := os.MkdirAll(filepath.Dir(full), 0o750); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(full, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
}
