package needs

import (
	"os"
	"path/filepath"
	"reflect"
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
			writeFile(t, filepath.Join(root, path), "name: update\n")
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

// TestMissingReportsASecretNeedThatTheRunDoesNotReceive (forsgren#73): a need
// of kind secret is in place when the environment variable it names is
// non-empty in the run, and missing when it is unset.
func TestMissingReportsASecretNeedThatTheRunDoesNotReceive(t *testing.T) {
	need := Need{Version: "0.3.8", Kind: "secret", Secret: "FORSGREN_TOKEN"}
	cases := []struct {
		name string
		env  map[string]string
		want []Need
	}{
		{"unset", map[string]string{}, []Need{need}},
		{"set", map[string]string{"FORSGREN_TOKEN": "token-value"}, nil},
	}
	for _, c := range cases {
		env := c.env
		got := Missing([]Need{need}, Installation{Getenv: func(k string) string { return env[k] }})
		if !reflect.DeepEqual(got, c.want) {
			t.Errorf("%s: want missing %v, got %v", c.name, c.want, got)
		}
	}
}

const callerWorkflow = ".github/workflows/forsgren.yml"

// templateHead and templateTail are the caller workflow of
// forsgren-template, cut after the grant of pages: the grants of its job,
// none of them for issues.
const (
	templateHead = `permissions: {}
jobs:
  metrics:
    permissions:
      contents: write
      pages: write
`
	templateTail = `      id-token: write
      pull-requests: read
    uses: yveshanoulle/forsgren/.github/workflows/metrics.yml@0123456789abcdef0123456789abcdef01234567 # v0.3.6
`
)

// templateWorkflow is the template's caller workflow, and the two after it
// the same with one more grant for the job: issues at write, and at read.
const (
	templateWorkflow = templateHead + templateTail
	withIssuesWrite  = templateHead + "      issues: write\n" + templateTail
	withIssuesRead   = templateHead + "      issues: read\n" + templateTail
	noWorkflow       = ""
	notYAMLWorkflow  = "jobs: [unclosed\n\t: : -\n"
)

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
	cases := []permissionCase{
		{"no workflow file", permissionNeed("write"), noWorkflow, false},
		{"template shape, no issues", permissionNeed("write"), templateWorkflow, false},
		{"issues write", permissionNeed("write"), withIssuesWrite, true},
		{"issues read only", permissionNeed("write"), withIssuesRead, false},
		{"not YAML", permissionNeed("write"), notYAMLWorkflow, false},
		{"write satisfies read", permissionNeed("read"), withIssuesWrite, true},
	}
	for _, c := range cases {
		c.assert(t)
	}
}

// permissionCase is a row of the permission test: the need, the caller
// workflow's content (noWorkflow for no file) and whether the need is in
// place.
type permissionCase struct {
	name     string
	need     Need
	workflow string
	inPlace  bool
}

// assert checks the need against a checkout holding the caller workflow.
func (c permissionCase) assert(t *testing.T) {
	t.Helper()
	root := t.TempDir()
	if c.workflow != noWorkflow {
		writeFile(t, filepath.Join(root, callerWorkflow), c.workflow)
	}
	var want []Need
	if !c.inPlace {
		want = []Need{c.need}
	}
	got := Missing([]Need{c.need}, Installation{Root: root})
	if !reflect.DeepEqual(got, want) {
		t.Errorf("%s: want missing %v, got %v", c.name, want, got)
	}
}

// writeFile writes the file at path with the content, with its directories.
func writeFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
}
